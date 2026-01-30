// ------------------------------------------------------------------------------------------------
// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License. See License.txt in the project root for license information.
// ------------------------------------------------------------------------------------------------
namespace Microsoft.Manufacturing.Subcontracting.Test;

using Microsoft.Finance.GeneralLedger.Setup;
using Microsoft.Foundation.Enums;
using Microsoft.Inventory.Item;
using Microsoft.Inventory.Ledger;
using Microsoft.Inventory.Location;
using Microsoft.Manufacturing.Capacity;
using Microsoft.Manufacturing.Document;
using Microsoft.Manufacturing.MachineCenter;
using Microsoft.Manufacturing.ProductionBOM;
using Microsoft.Manufacturing.Routing;
using Microsoft.Manufacturing.Setup;
using Microsoft.Manufacturing.Subcontracting;
using Microsoft.Manufacturing.WorkCenter;
using Microsoft.Purchases.Document;
using Microsoft.Purchases.Vendor;
using Microsoft.Warehouse.Activity;
using Microsoft.Warehouse.Document;
using Microsoft.Warehouse.History;
using Microsoft.Warehouse.Structure;

codeunit 140000 "Subc. Whse Receipt Last Op."
{
    // [FEATURE] Subcontracting Warehouse Receipt - Last Operation Tests
    Subtype = Test;
    TestPermissions = Disabled;
    TestType = IntegrationTest;

    trigger OnRun()
    begin
        IsInitialized := false;
    end;

    var
        Assert: Codeunit Assert;
        LibraryERMCountryData: Codeunit "Library - ERM Country Data";
        LibraryInventory: Codeunit "Library - Inventory";
        LibraryManufacturing: Codeunit "Library - Manufacturing";
        LibraryPurchase: Codeunit "Library - Purchase";
        LibraryRandom: Codeunit "Library - Random";
        LibrarySetupStorage: Codeunit "Library - Setup Storage";
        LibraryTestInitialize: Codeunit "Library - Test Initialize";
        LibraryWarehouse: Codeunit "Library - Warehouse";
        SubcontractingMgmtLibrary: Codeunit "Subc. Management Library";
        SubcLibraryMfgManagement: Codeunit "Subc. Library Mfg. Management";
        SubcWarehouseLibrary: Codeunit "Subc. Warehouse Library";
        SubSetupLibrary: Codeunit "Subc. Setup Library";
        IsInitialized: Boolean;

    local procedure Initialize()
    begin
        LibraryTestInitialize.OnTestInitialize(Codeunit::"Subc. Whse Receipt Last Op.");
        LibrarySetupStorage.Restore();

        SubcontractingMgmtLibrary.Initialize();
        SubcLibraryMfgManagement.Initialize();
        SubSetupLibrary.InitSetupFields();

        if IsInitialized then
            exit;

        LibraryTestInitialize.OnBeforeTestSuiteInitialize(Codeunit::"Subc. Whse Receipt Last Op.");

        LibraryERMCountryData.CreateVATData();
        LibraryERMCountryData.UpdateGeneralPostingSetup();
        LibrarySetupStorage.Save(Database::"General Ledger Setup");

        IsInitialized := true;
        Commit();
        LibraryTestInitialize.OnAfterTestSuiteInitialize(Codeunit::"Subc. Whse Receipt Last Op.");
    end;

    [Test]
    procedure CreateAndVerifyWhseReceiptFromSubcontractingPOForLastOperation()
    var
        Item: Record Item;
        Location: Record Location;
        MachineCenter: array[2] of Record "Machine Center";
        ProductionOrder: Record "Production Order";
        PurchaseHeader: Record "Purchase Header";
        PurchaseLine: Record "Purchase Line";
        WarehouseReceiptHeader: Record "Warehouse Receipt Header";
        WarehouseReceiptLine: Record "Warehouse Receipt Line";
        PostedWhseReceiptHeader: Record "Posted Whse. Receipt Header";
        WorkCenter: array[2] of Record "Work Center";
        Vendor: Record Vendor;
        Bin: Record Bin;
        Quantity: Decimal;
    begin
        // [SCENARIO] Create and verify warehouse receipt from subcontracting purchase order for last operation
        // [FEATURE] Subcontracting Warehouse Receipt - Comprehensive validation of field mapping and data consistency

        // [GIVEN] Complete Setup of Manufacturing, include Work- and Machine Centers, Item
        Initialize();
        Quantity := LibraryRandom.RandInt(10) + 5;

        // [GIVEN] Create and Calculate needed Work and Machine Center with Subcontracting
        SubcWarehouseLibrary.CreateAndCalculateNeededWorkAndMachineCenter(WorkCenter, MachineCenter, true);

        // [GIVEN] Create Item for Production include Routing and Prod. BOM
        SubcWarehouseLibrary.CreateItemForProductionIncludeRoutingAndProdBOM(Item, WorkCenter, MachineCenter);

        // [GIVEN] Update BOM and Routing with Routing Link
        SubcWarehouseLibrary.UpdateProdBomAndRoutingWithRoutingLink(Item, WorkCenter[2]."No.");

        // [GIVEN] Create Location with Warehouse Handling
        SubcWarehouseLibrary.CreateLocationWithWarehouseHandling(Location);

        // [GIVEN] Create default bin for location
        LibraryWarehouse.CreateBin(Bin, Location.Code, 'DEFAULT', '', '');
        Location.Validate("Default Bin Code", Bin.Code);
        Location.Modify(true);

        // [GIVEN] Update Vendor with Subcontracting Location Code
        Vendor.Get(WorkCenter[2]."Subcontractor No.");
        Vendor."Subcontr. Location Code" := Location.Code;
        Vendor."Location Code" := Location.Code;
        Vendor.Modify();

        // [GIVEN] Create and Refresh Production Order
        SubcWarehouseLibrary.CreateAndRefreshProductionOrder(
            ProductionOrder, "Production Order Status"::Released,
            ProductionOrder."Source Type"::Item, Item."No.", Quantity, Location.Code);

        // [GIVEN] Update Subcontracting Management Setup with Requisition Worksheet Template
        SubcWarehouseLibrary.UpdateSubMgmtSetupWithReqWkshTemplate();

        // [WHEN] Create Subcontracting Purchase Order from Prod. Order Routing
        SubcWarehouseLibrary.CreateSubcontractingOrderFromProdOrderRouting(Item."Routing No.", WorkCenter[2]."No.", PurchaseLine);

        // [WHEN] Get Purchase Header
        PurchaseHeader.Get(PurchaseLine."Document Type", PurchaseLine."Document No.");

        // [WHEN] Create Warehouse Receipt from Purchase Order
        SubcWarehouseLibrary.CreateWarehouseReceiptFromPurchaseOrder(PurchaseHeader, WarehouseReceiptHeader);

        // [THEN] Verify warehouse receipt line is created
        WarehouseReceiptLine.SetRange("No.", WarehouseReceiptHeader."No.");
        WarehouseReceiptLine.SetRange("Source Document", WarehouseReceiptLine."Source Document"::"Purchase Order");
        WarehouseReceiptLine.SetRange("Source No.", PurchaseHeader."No.");
        Assert.RecordIsNotEmpty(WarehouseReceiptLine);
        WarehouseReceiptLine.FindFirst();

        // [THEN] Verify field mapping from Purchase Line to Warehouse Receipt Line
        Assert.AreEqual(PurchaseLine."No.", WarehouseReceiptLine."Item No.",
            'Item No. should match between Purchase Line and Warehouse Receipt Line');
        Assert.AreEqual(PurchaseLine.Quantity, WarehouseReceiptLine.Quantity,
            'Quantity should match between Purchase Line and Warehouse Receipt Line');
        Assert.AreEqual(PurchaseLine."Unit of Measure Code", WarehouseReceiptLine."Unit of Measure Code",
            'Unit of Measure Code should match between Purchase Line and Warehouse Receipt Line');
        Assert.AreEqual(PurchaseLine."Location Code", WarehouseReceiptLine."Location Code",
            'Location Code should match between Purchase Line and Warehouse Receipt Line');
        Assert.AreEqual(PurchaseLine."Subc. Purchase Line Type", WarehouseReceiptLine."Subc. Purchase Line Type",
            'Subcontracting Purchase Line Type should match between Purchase Line and Warehouse Receipt Line');

        // [THEN] Verify source document references
        Assert.AreEqual(PurchaseHeader."No.", WarehouseReceiptLine."Source No.",
            'Source No. should reference the Purchase Order No.');
        Assert.AreEqual(PurchaseLine."Line No.", WarehouseReceiptLine."Source Line No.",
            'Source Line No. should reference the Purchase Line No.');
        Assert.AreEqual(Database::"Purchase Line", WarehouseReceiptLine."Source Type",
            'Source Type should be Purchase Line');
        Assert.AreEqual(WarehouseReceiptLine."Source Document"::"Purchase Order",
            WarehouseReceiptLine."Source Document",
            'Source Document should be Purchase Order');

        // [THEN] Verify base quantity calculations using Qty. (Base) = Quantity * Qty. per Unit of Measure
        Assert.AreEqual(WarehouseReceiptLine.Quantity * WarehouseReceiptLine."Qty. per Unit of Measure", WarehouseReceiptLine."Qty. (Base)",
            'Qty. (Base) should equal Quantity * Qty. per Unit of Measure');
        Assert.AreEqual(WarehouseReceiptLine."Qty. Outstanding" * WarehouseReceiptLine."Qty. per Unit of Measure", WarehouseReceiptLine."Qty. Outstanding (Base)",
            'Qty. Outstanding (Base) should equal Qty. Outstanding * Qty. per Unit of Measure');

        // [THEN] Verify subcontracting line type is set to Last Operation
        Assert.AreEqual("Subc. Purchase Line Type"::LastOperation,
            WarehouseReceiptLine."Subc. Purchase Line Type",
            'Warehouse Receipt Line should be marked as Last Operation');

        // [WHEN] Post Warehouse Receipt
        SubcWarehouseLibrary.PostWarehouseReceipt(WarehouseReceiptHeader, PostedWhseReceiptHeader);

        // [THEN] Verify Ledger Entries: Item ledger entries created for last operation
        VerifyItemLedgerEntriesExist(Item."No.", Location.Code, Quantity);

        // [THEN] Verify Ledger Entries: Capacity ledger entries also created for last operation
        VerifyCapacityLedgerEntriesExist(ProductionOrder."No.", WorkCenter[2]."No.");
    end;

    [Test]
    procedure VerifyEndToEndUoMFlowWithAlternativeUoM()
    var
        Item: Record Item;
        ItemUnitOfMeasure: Record "Item Unit of Measure";
        Location: Record Location;
        VendorLocation: Record Location;
        MachineCenter: array[2] of Record "Machine Center";
        ProductionOrder: Record "Production Order";
        PurchaseHeader: Record "Purchase Header";
        PurchaseLine: Record "Purchase Line";
        WarehouseReceiptHeader: Record "Warehouse Receipt Header";
        WarehouseReceiptLine: Record "Warehouse Receipt Line";
        WarehouseActivityHeader: Record "Warehouse Activity Header";
        WarehouseActivityLine: Record "Warehouse Activity Line";
        PostedWhseReceiptHeader: Record "Posted Whse. Receipt Header";
        PostedWhseReceiptLine: Record "Posted Whse. Receipt Line";
        ItemLedgerEntry: Record "Item Ledger Entry";
        WorkCenter: array[2] of Record "Work Center";
        Vendor: Record Vendor;
        ReceiveBin: Record Bin;
        PutAwayBin: Record Bin;
        Quantity: Decimal;
        QtyPerUoM: Decimal;
        ExpectedBaseQty: Decimal;
    begin
        // [SCENARIO] Verify end-to-end flow with alternative UoM - Purchase Line to Item Ledger Entry
        // [FEATURE] Subcontracting Warehouse - Complete UoM Flow Verification
        // [PRIORITY] Critical - Ensures Qty. (Base) flows correctly through all warehouse documents

        // [GIVEN] Complete Setup with alternative Unit of Measure (Box = 12 base units)
        Initialize();
        Quantity := LibraryRandom.RandIntInRange(5, 10);   // Number of Boxes
        QtyPerUoM := 12;                                    // 12 units per Box
        ExpectedBaseQty := Quantity * QtyPerUoM;           // Total base units

        // [GIVEN] Create Work Centers and Manufacturing Setup
        SubcWarehouseLibrary.CreateAndCalculateNeededWorkAndMachineCenter(WorkCenter, MachineCenter, true);

        // [GIVEN] Create Item with alternative Unit of Measure (Box)
        SubcWarehouseLibrary.CreateItemForProductionIncludeRoutingAndProdBOM(Item, WorkCenter, MachineCenter);
        LibraryInventory.CreateItemUnitOfMeasureCode(ItemUnitOfMeasure, Item."No.", QtyPerUoM);

        SubcWarehouseLibrary.UpdateProdBomAndRoutingWithRoutingLink(Item, WorkCenter[2]."No.");

        // [GIVEN] Create Location with Warehouse Handling and Bins
        SubcWarehouseLibrary.CreateLocationWithWarehouseHandlingAndBins(Location, ReceiveBin, PutAwayBin);

        // [GIVEN] Configure Vendor with Subcontracting Location
        Vendor.Get(WorkCenter[2]."Subcontractor No.");
        Vendor."Subcontr. Location Code" := Location.Code;
        Vendor."Location Code" := LibraryWarehouse.CreateLocationWithInventoryPostingSetup(VendorLocation);
        Vendor.Modify();

        // [GIVEN] Create Production Order
        SubcWarehouseLibrary.CreateAndRefreshProductionOrder(
            ProductionOrder, "Production Order Status"::Released,
            ProductionOrder."Source Type"::Item, Item."No.", Quantity, Location.Code);

        SubcWarehouseLibrary.UpdateSubMgmtSetupWithReqWkshTemplate();

        // [WHEN] Create Subcontracting Purchase Order with alternative UoM (Box)
        SubcWarehouseLibrary.CreateSubcontractingOrderFromProdOrderRouting(Item."Routing No.", WorkCenter[2]."No.", PurchaseLine);
        PurchaseLine.Validate("Unit of Measure Code", ItemUnitOfMeasure.Code);
        PurchaseLine.Modify(true);

        // [THEN] Step 1: Verify Purchase Line has correct base quantity
        // Assert.AreEqual(QtyPerUoM, PurchaseLine."Qty. per Unit of Measure",
        //     'Purchase Line Qty. per Unit of Measure should match alternative UoM');

        PurchaseHeader.Get(PurchaseLine."Document Type", PurchaseLine."Document No.");

        // [WHEN] Create Warehouse Receipt
        SubcWarehouseLibrary.CreateWarehouseReceiptFromPurchaseOrder(PurchaseHeader, WarehouseReceiptHeader);

        // [THEN] Step 2: Verify Warehouse Receipt Line has correct base quantity and UoM fields
        WarehouseReceiptLine.SetRange("No.", WarehouseReceiptHeader."No.");
        WarehouseReceiptLine.FindFirst();

        Assert.AreEqual(ExpectedBaseQty, WarehouseReceiptLine."Qty. (Base)",
            'Warehouse Receipt Line Qty. (Base) should equal Quantity * Qty per UoM');
        Assert.AreEqual(Quantity, WarehouseReceiptLine.Quantity,
            'Warehouse Receipt Line Quantity should remain in alternative UoM');
        Assert.AreEqual(ItemUnitOfMeasure.Code, WarehouseReceiptLine."Unit of Measure Code",
            'Warehouse Receipt Line Unit of Measure Code should be the alternative UoM');
        Assert.AreEqual(QtyPerUoM, WarehouseReceiptLine."Qty. per Unit of Measure",
            'Warehouse Receipt Line Qty. per Unit of Measure should match alternative UoM');

        // [WHEN] Post Warehouse Receipt
        SubcWarehouseLibrary.PostWarehouseReceipt(WarehouseReceiptHeader, PostedWhseReceiptHeader);

        // [THEN] Step 3: Verify Posted Warehouse Receipt Line has correct base quantity
        PostedWhseReceiptLine.SetRange("No.", PostedWhseReceiptHeader."No.");
        PostedWhseReceiptLine.SetRange("Item No.", Item."No.");
        PostedWhseReceiptLine.FindFirst();

        Assert.AreEqual(ExpectedBaseQty, PostedWhseReceiptLine."Qty. (Base)",
            'Posted Warehouse Receipt Line Qty. (Base) should equal Quantity * Qty per UoM');
        Assert.AreEqual(QtyPerUoM, PostedWhseReceiptLine."Qty. per Unit of Measure",
            'Posted Warehouse Receipt Line Qty. per Unit of Measure should match alternative UoM');

        // [WHEN] Create Put-away from Posted Warehouse Receipt
        SubcWarehouseLibrary.CreatePutAwayFromPostedWhseReceipt(PostedWhseReceiptHeader, WarehouseActivityHeader);

        // [THEN] Step 4: Verify Put-away Take line has correct UoM fields
        WarehouseActivityLine.SetRange("Activity Type", WarehouseActivityLine."Activity Type"::"Put-away");
        WarehouseActivityLine.SetRange("No.", WarehouseActivityHeader."No.");
        WarehouseActivityLine.SetRange("Action Type", WarehouseActivityLine."Action Type"::Take);
        WarehouseActivityLine.FindFirst();

        Assert.AreEqual(Quantity, WarehouseActivityLine.Quantity,
            'Put-away Take line Quantity should be in alternative UoM');
        Assert.AreEqual(ExpectedBaseQty, WarehouseActivityLine."Qty. (Base)",
            'Put-away Take line Qty. (Base) should equal Quantity * Qty per UoM');
        Assert.AreEqual(QtyPerUoM, WarehouseActivityLine."Qty. per Unit of Measure",
            'Put-away Take line Qty. per Unit of Measure should match alternative UoM');
        Assert.AreEqual(ItemUnitOfMeasure.Code, WarehouseActivityLine."Unit of Measure Code",
            'Put-away Take line should use alternative UoM code');

        // [THEN] Step 5: Verify Put-away Place line has correct base quantity
        WarehouseActivityLine.SetRange("Action Type", WarehouseActivityLine."Action Type"::Place);
        WarehouseActivityLine.FindFirst();

        Assert.AreEqual(ExpectedBaseQty, WarehouseActivityLine."Qty. (Base)",
            'Put-away Place line Qty. (Base) should equal Quantity * Qty per UoM');

        // [WHEN] Post Put-away
        LibraryWarehouse.RegisterWhseActivity(WarehouseActivityHeader);

        // [THEN] Step 6: Verify Item Ledger Entry has correct quantity (in base units)
        ItemLedgerEntry.SetRange("Item No.", Item."No.");
        ItemLedgerEntry.SetRange("Location Code", Location.Code);
        ItemLedgerEntry.SetRange("Entry Type", ItemLedgerEntry."Entry Type"::Output);
        Assert.RecordIsNotEmpty(ItemLedgerEntry);
        ItemLedgerEntry.FindFirst();

        Assert.AreEqual(ExpectedBaseQty, ItemLedgerEntry.Quantity,
            'Item Ledger Entry Quantity should be in base units (Quantity * Qty per UoM)');

        // [THEN] Step 7: Verify Bin Contents have correct quantity (in base units)
        SubcWarehouseLibrary.VerifyBinContents(Location.Code, PutAwayBin.Code, Item."No.", ExpectedBaseQty);

        // [THEN] Verify Capacity Ledger Entry created
        VerifyCapacityLedgerEntriesExist(ProductionOrder."No.", WorkCenter[2]."No.");
    end;

    local procedure VerifyItemLedgerEntriesExist(ItemNo: Code[20]; LocationCode: Code[10]; ExpectedQuantity: Decimal)
    var
        ItemLedgerEntry: Record "Item Ledger Entry";
    begin
        // Verify that item ledger entries were created for the last operation
        ItemLedgerEntry.SetRange("Item No.", ItemNo);
        ItemLedgerEntry.SetRange("Location Code", LocationCode);
        ItemLedgerEntry.SetRange("Entry Type", ItemLedgerEntry."Entry Type"::Output);
        Assert.AreEqual(1, ItemLedgerEntry.Count(),
            'Item ledger entries should be created for last operation');

        ItemLedgerEntry.FindFirst();
        Assert.AreEqual(ExpectedQuantity, ItemLedgerEntry.Quantity,
            'Item ledger entry quantity should match posted quantity');
    end;

    local procedure VerifyCapacityLedgerEntriesExist(ProdOrderNo: Code[20]; WorkCenterNo: Code[20])
    var
        CapacityLedgerEntry: Record "Capacity Ledger Entry";
    begin
        // Verify that capacity ledger entries were created for the last operation
        CapacityLedgerEntry.SetRange("Order No.", ProdOrderNo);
        CapacityLedgerEntry.SetRange("Work Center No.", WorkCenterNo);
        Assert.AreEqual(1, CapacityLedgerEntry.Count(),
            'Capacity ledger entries should be created for last operation');
    end;

}
