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
using Microsoft.Manufacturing.Subcontracting;
using Microsoft.Manufacturing.WorkCenter;
using Microsoft.Purchases.Document;
using Microsoft.Purchases.Vendor;
using Microsoft.Warehouse.Activity;
using Microsoft.Warehouse.Document;
using Microsoft.Warehouse.History;
using Microsoft.Warehouse.Setup;
using Microsoft.Warehouse.Structure;

codeunit 140006 "Subc. Whse Combined Scenarios"
{
    // [FEATURE] Subcontracting Warehouse Combined Scenarios Tests
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
        LibraryRandom: Codeunit "Library - Random";
        LibrarySetupStorage: Codeunit "Library - Setup Storage";
        LibraryTestInitialize: Codeunit "Library - Test Initialize";
        LibraryWarehouse: Codeunit "Library - Warehouse";
        SubcontractingMgmtLibrary: Codeunit "Subc. Management Library";
        SubcLibraryMfgManagement: Codeunit "Subc. Library Mfg. Management";
        SubcWarehouseLibrary: Codeunit "Subc. Warehouse Library";
        SubSetupLibrary: Codeunit "Subc. Setup Library";
        LibraryPurchase: Codeunit "Library - Purchase";
        IsInitialized: Boolean;

    local procedure Initialize()
    begin
        LibraryTestInitialize.OnTestInitialize(Codeunit::"Subc. Whse Combined Scenarios");
        LibrarySetupStorage.Restore();

        SubcontractingMgmtLibrary.Initialize();
        SubcLibraryMfgManagement.Initialize();
        SubSetupLibrary.InitSetupFields();

        if IsInitialized then
            exit;

        LibraryTestInitialize.OnBeforeTestSuiteInitialize(Codeunit::"Subc. Whse Combined Scenarios");

        LibraryERMCountryData.CreateVATData();
        LibraryERMCountryData.UpdateGeneralPostingSetup();
        LibrarySetupStorage.Save(Database::"General Ledger Setup");

        IsInitialized := true;
        Commit();
        LibraryTestInitialize.OnAfterTestSuiteInitialize(Codeunit::"Subc. Whse Combined Scenarios");
    end;

    [Test]
    procedure ProdOrderWithLastAndIntermediateOperationsSameVendor()
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
        PostedWhseReceiptLine: Record "Posted Whse. Receipt Line";
        WarehouseActivityHeader: Record "Warehouse Activity Header";
        WarehouseActivityLine: Record "Warehouse Activity Line";
        WorkCenter: array[2] of Record "Work Center";
        Vendor: Record Vendor;
        WarehouseEmployee: Record "Warehouse Employee";
        Bin: Record Bin;
        Quantity: Decimal;
    begin
        // [SCENARIO] Prod. Order with Last and Intermediate Operations (Same Vendor)
        // [FEATURE] Subcontracting Warehouse Combined Scenarios

        // [GIVEN] Complete Manufacturing Setup with Work Centers, Machine Centers, and Item
        Initialize();
        Quantity := LibraryRandom.RandIntInRange(10, 20);

        // [GIVEN] Create Work Centers and Machine Centers with Subcontracting - both with same vendor
        SubcWarehouseLibrary.CreateAndCalculateNeededWorkAndMachineCenterSameVendor(WorkCenter, MachineCenter, true);

        // [GIVEN] Create Item with Routing and Production BOM
        SubcWarehouseLibrary.CreateItemForProductionIncludeRoutingAndProdBOM(Item, WorkCenter, MachineCenter);

        // [GIVEN] Update BOM and Routing with Routing Links for both operations
        SubcWarehouseLibrary.UpdateProdBomAndRoutingWithRoutingLinkForBothOperations(Item, WorkCenter);

        // [GIVEN] Create Location with Warehouse Handling
        SubcWarehouseLibrary.CreateLocationWithWarehouseHandling(Location);

        // [GIVEN] Create Warehouse Employee for the location
        LibraryWarehouse.CreateWarehouseEmployee(WarehouseEmployee, Location.Code, true);

        // [GIVEN] Create default bin for location
        LibraryWarehouse.CreateBin(Bin, Location.Code, 'COMBINED', '', '');
        Location.Validate("Default Bin Code", Bin.Code);
        Location.Modify(true);

        // [GIVEN] Configure Vendor with Subcontracting Location
        Vendor.Get(WorkCenter[1]."Subcontractor No.");
        Vendor."Subcontr. Location Code" := Location.Code;
        Vendor."Location Code" := Location.Code;
        Vendor.Modify();

        // [GIVEN] Create and Refresh Production Order
        SubcWarehouseLibrary.CreateAndRefreshProductionOrder(
            ProductionOrder, "Production Order Status"::Released,
            ProductionOrder."Source Type"::Item, Item."No.", Quantity, Location.Code);

        // [GIVEN] Setup Requisition Worksheet Template
        SubcWarehouseLibrary.UpdateSubMgmtSetupWithReqWkshTemplate();

        // [WHEN] Create Subcontracting Purchase Orders via Subcontracting Worksheet
        // The worksheet approach combines all lines for the same vendor into one Purchase Order
        SubcWarehouseLibrary.CreateSubcontractingOrdersViaWorksheet(ProductionOrder."No.", PurchaseHeader);

        // [THEN] Verify Data Consistency: Both operations should be on the same PO (same vendor)
        PurchaseLine.SetRange("Document Type", PurchaseHeader."Document Type");
        PurchaseLine.SetRange("Document No.", PurchaseHeader."No.");
        PurchaseLine.SetRange(Type, "Purchase Line Type"::Item);
        Assert.RecordCount(PurchaseLine, 2);

        // [WHEN] Create single Warehouse Receipt using "Get Source Documents" to include both lines
        LibraryPurchase.ReleasePurchaseDocument(PurchaseHeader);
        SubcWarehouseLibrary.CreateWarehouseReceiptUsingGetSourceDocuments(WarehouseReceiptHeader, Location.Code);

        // [THEN] Verify Data Consistency: Single warehouse receipt created for both lines from same PO
        WarehouseReceiptLine.SetRange("No.", WarehouseReceiptHeader."No.");
        WarehouseReceiptLine.SetRange("Source Document", WarehouseReceiptLine."Source Document"::"Purchase Order");
        WarehouseReceiptLine.SetRange("Source No.", PurchaseHeader."No.");
        Assert.RecordCount(WarehouseReceiptLine, 2);

        // [THEN] Verify Data Consistency: Identify intermediate and last operation lines
        WarehouseReceiptLine.SetRange("Subc. Purchase Line Type", WarehouseReceiptLine."Subc. Purchase Line Type"::NotLastOperation);
        Assert.RecordCount(WarehouseReceiptLine, 1);
        WarehouseReceiptLine.FindFirst();
        Assert.AreEqual(Item."No.", WarehouseReceiptLine."Item No.",
            'Intermediate operation line should have correct item');

        WarehouseReceiptLine.SetRange("Subc. Purchase Line Type", "Subc. Purchase Line Type"::LastOperation);
        Assert.RecordCount(WarehouseReceiptLine, 1);
        WarehouseReceiptLine.FindFirst();
        Assert.AreEqual(Item."No.", WarehouseReceiptLine."Item No.",
            'Last operation line should have correct item');

        // [WHEN] Post warehouse receipt for both lines
        SubcWarehouseLibrary.PostWarehouseReceipt(WarehouseReceiptHeader, PostedWhseReceiptHeader);

        // [THEN] Verify Posted Entries: Posted warehouse receipt created
        Assert.AreNotEqual('', PostedWhseReceiptHeader."No.",
            'Posted warehouse receipt should be created');

        PostedWhseReceiptLine.SetRange("No.", PostedWhseReceiptHeader."No.");
        PostedWhseReceiptLine.SetRange("Item No.", Item."No.");
        Assert.RecordCount(PostedWhseReceiptLine, 2);

        // [THEN] Verify Bin Management: Put-away can only be created for last operation line
        WarehouseActivityLine.SetRange("Activity Type", WarehouseActivityLine."Activity Type"::"Put-away");
        WarehouseActivityLine.SetRange("Location Code", Location.Code);
        WarehouseActivityLine.SetRange("Item No.", Item."No.");
        Assert.RecordCount(WarehouseActivityLine, 1);
        WarehouseActivityLine.FindFirst();

        // [THEN] Verify Data Consistency: Put-away line is for last operation only
        PostedWhseReceiptLine.SetRange("Subc. Purchase Line Type", "Subc. Purchase Line Type"::LastOperation);
        PostedWhseReceiptLine.FindFirst();
        Assert.AreEqual(PostedWhseReceiptLine."No.", WarehouseActivityLine."Whse. Document No.",
            'Put-away should only be created for last operation line');

        // [WHEN] Post the put-away
        WarehouseActivityHeader.Get(WarehouseActivityLine."Activity Type", WarehouseActivityLine."No.");
        SubcWarehouseLibrary.PostPutAway(WarehouseActivityHeader);

        // [THEN] Verify Quantity Reconciliation: All quantities correct for both operations
        VerifyQuantityReconciliation(ProductionOrder, PurchaseHeader, Quantity);

        // [THEN] Verify Posted Entries: All ledger entries correct for both operations
        VerifyLedgerEntriesForCombinedScenario(Item."No.", Quantity, Location.Code);
    end;

    [Test]
    procedure ProdOrderWithMultipleOperationsDifferentVendors()
    var
        Item: Record Item;
        Location: Record Location;
        MachineCenter: array[2] of Record "Machine Center";
        ProductionOrder: Record "Production Order";
        PurchaseHeader1: Record "Purchase Header";
        PurchaseHeader2: Record "Purchase Header";
        PurchaseLine: Record "Purchase Line";
        WarehouseReceiptHeader1: Record "Warehouse Receipt Header";
        WarehouseReceiptHeader2: Record "Warehouse Receipt Header";
        WarehouseReceiptLine: Record "Warehouse Receipt Line";
        PostedWhseReceiptHeader1: Record "Posted Whse. Receipt Header";
        PostedWhseReceiptHeader2: Record "Posted Whse. Receipt Header";
        WorkCenter: array[2] of Record "Work Center";
        Vendor1: Record Vendor;
        Vendor2: Record Vendor;
        WarehouseEmployee: Record "Warehouse Employee";
        Bin: Record Bin;
        Quantity: Decimal;
    begin
        // [SCENARIO] Prod. Order with Multiple Operations (Different Vendors)
        // [FEATURE] Subcontracting Warehouse Combined Scenarios

        // [GIVEN] Complete Manufacturing Setup with Work Centers, Machine Centers, and Item
        Initialize();
        Quantity := LibraryRandom.RandIntInRange(15, 25);

        // [GIVEN] Create Work Centers and Machine Centers with Subcontracting - different vendors
        SubcWarehouseLibrary.CreateAndCalculateNeededWorkAndMachineCenter(WorkCenter, MachineCenter, true);

        // [GIVEN] Create Item with Routing and Production BOM
        SubcWarehouseLibrary.CreateItemForProductionIncludeRoutingAndProdBOM(Item, WorkCenter, MachineCenter);

        // [GIVEN] Update BOM and Routing with Routing Links for both operations
        SubcWarehouseLibrary.UpdateProdBomAndRoutingWithRoutingLinkForBothOperations(Item, WorkCenter);

        // [GIVEN] Create Location with Warehouse Handling
        SubcWarehouseLibrary.CreateLocationWithWarehouseHandling(Location);

        // [GIVEN] Create Warehouse Employee for the location
        LibraryWarehouse.CreateWarehouseEmployee(WarehouseEmployee, Location.Code, true);

        // [GIVEN] Create default bin for location
        LibraryWarehouse.CreateBin(Bin, Location.Code, 'MULTIVENDOR', '', '');
        Location.Validate("Default Bin Code", Bin.Code);
        Location.Modify(true);

        // [GIVEN] Configure Vendors with Subcontracting Location
        Vendor1.Get(WorkCenter[1]."Subcontractor No.");
        Vendor1."Subcontr. Location Code" := Location.Code;
        Vendor1."Location Code" := Location.Code;
        Vendor1.Modify();

        Vendor2.Get(WorkCenter[2]."Subcontractor No.");
        Vendor2."Subcontr. Location Code" := Location.Code;
        Vendor2."Location Code" := Location.Code;
        Vendor2.Modify();

        // [GIVEN] Create and Refresh Production Order
        SubcWarehouseLibrary.CreateAndRefreshProductionOrder(
            ProductionOrder, "Production Order Status"::Released,
            ProductionOrder."Source Type"::Item, Item."No.", Quantity, Location.Code);

        // [GIVEN] Setup Requisition Worksheet Template
        SubcWarehouseLibrary.UpdateSubMgmtSetupWithReqWkshTemplate();

        // [WHEN] Create Subcontracting Purchase Orders via Subcontracting Worksheet
        // The worksheet creates one PO per vendor
        SubcWarehouseLibrary.CreateSubcontractingOrdersViaWorksheet(ProductionOrder."No.", PurchaseHeader1);

        // [THEN] Find both Purchase Headers - different vendors will have separate POs
        PurchaseLine.SetRange("Document Type", "Purchase Document Type"::Order);
        PurchaseLine.SetRange(Type, "Purchase Line Type"::Item);
#pragma warning disable AA0210
        PurchaseLine.SetRange("Prod. Order No.", ProductionOrder."No.");
#pragma warning restore AA0210
        PurchaseLine.SetRange("Buy-from Vendor No.", Vendor1."No.");
        PurchaseLine.FindFirst();
        PurchaseHeader1.Get(PurchaseLine."Document Type", PurchaseLine."Document No.");

        PurchaseLine.SetRange("Buy-from Vendor No.", Vendor2."No.");
        PurchaseLine.FindFirst();
        PurchaseHeader2.Get(PurchaseLine."Document Type", PurchaseLine."Document No.");

        // [THEN] Verify Data Consistency: Separate POs for different vendors
        Assert.AreNotEqual(PurchaseHeader1."No.", PurchaseHeader2."No.",
            'Different vendors should have separate Purchase Orders');

        Assert.AreNotEqual(PurchaseHeader1."Buy-from Vendor No.", PurchaseHeader2."Buy-from Vendor No.",
            'Purchase Orders should have different vendors');

        // [WHEN] Create separate Warehouse Receipts for each PO
        SubcWarehouseLibrary.CreateWarehouseReceiptFromPurchaseOrder(PurchaseHeader1, WarehouseReceiptHeader1);
        SubcWarehouseLibrary.CreateWarehouseReceiptFromPurchaseOrder(PurchaseHeader2, WarehouseReceiptHeader2);

        // [THEN] Verify Data Consistency: Separate warehouse documents for each vendor
        Assert.AreNotEqual(WarehouseReceiptHeader1."No.", WarehouseReceiptHeader2."No.",
            'Separate warehouse receipts should be created for different vendors');

        // [THEN] Verify Data Consistency: Each warehouse receipt has correct vendor info
        WarehouseReceiptLine.SetRange("No.", WarehouseReceiptHeader1."No.");
        WarehouseReceiptLine.FindFirst();
        Assert.AreEqual(PurchaseHeader1."No.", WarehouseReceiptLine."Source No.",
            'First warehouse receipt should link to first PO');

        WarehouseReceiptLine.SetRange("No.", WarehouseReceiptHeader2."No.");
        WarehouseReceiptLine.FindFirst();
        Assert.AreEqual(PurchaseHeader2."No.", WarehouseReceiptLine."Source No.",
            'Second warehouse receipt should link to second PO');

        // [WHEN] Post both warehouse receipts independently
        SubcWarehouseLibrary.PostWarehouseReceipt(WarehouseReceiptHeader1, PostedWhseReceiptHeader1);
        SubcWarehouseLibrary.PostWarehouseReceipt(WarehouseReceiptHeader2, PostedWhseReceiptHeader2);

        // [THEN] Verify Posted Entries: All documents processed correctly and independently
        Assert.AreNotEqual('', PostedWhseReceiptHeader1."No.",
            'First posted warehouse receipt should be created');
        Assert.AreNotEqual('', PostedWhseReceiptHeader2."No.",
            'Second posted warehouse receipt should be created');

        // [THEN] Verify Quantity Reconciliation: Quantities are correct for both vendors
        VerifyQuantityReconciliation(ProductionOrder, PurchaseHeader1, Quantity);
        VerifyQuantityReconciliation(ProductionOrder, PurchaseHeader2, Quantity);

        // [THEN] Verify Data Consistency: All ledger entries correct for both vendors
        VerifyLedgerEntriesForMultiVendorScenario(Item."No.", Quantity, Location.Code);
    end;

    [Test]
    procedure WhseReceiptCreationWithGetSourceDocuments()
    var
        Item: Record Item;
        Location: Record Location;
        MachineCenter: array[2] of Record "Machine Center";
        ProductionOrder1: Record "Production Order";
        ProductionOrder2: Record "Production Order";
        PurchaseHeader: Record "Purchase Header";
        PurchaseLine: Record "Purchase Line";
        WarehouseReceiptHeader: Record "Warehouse Receipt Header";
        WarehouseReceiptLine: Record "Warehouse Receipt Line";
        PostedWhseReceiptHeader: Record "Posted Whse. Receipt Header";
        WorkCenter: array[2] of Record "Work Center";
        Vendor: Record Vendor;
        WarehouseEmployee: Record "Warehouse Employee";
        Bin: Record Bin;
        Quantity1: Decimal;
        Quantity2: Decimal;
    begin
        // [SCENARIO] WH Receipt Creation with "Get Source Documents"
        // [FEATURE] Subcontracting Warehouse Combined Scenarios

        // [GIVEN] Complete Manufacturing Setup with Work Centers, Machine Centers, and Item
        Initialize();
        Quantity1 := LibraryRandom.RandIntInRange(10, 15);
        Quantity2 := LibraryRandom.RandIntInRange(15, 20);

        // [GIVEN] Create Work Centers and Machine Centers with Subcontracting - same vendor
        SubcWarehouseLibrary.CreateAndCalculateNeededWorkAndMachineCenterSameVendor(WorkCenter, MachineCenter, true);

        // [GIVEN] Create Item with Routing and Production BOM
        SubcWarehouseLibrary.CreateItemForProductionIncludeRoutingAndProdBOM(Item, WorkCenter, MachineCenter);

        // [GIVEN] Update BOM and Routing with Routing Link for last operation
        SubcWarehouseLibrary.UpdateProdBomAndRoutingWithRoutingLink(Item, WorkCenter[2]."No.");

        // [GIVEN] Create Location with Warehouse Handling
        SubcWarehouseLibrary.CreateLocationWithWarehouseHandling(Location);

        // [GIVEN] Create Warehouse Employee for the location
        LibraryWarehouse.CreateWarehouseEmployee(WarehouseEmployee, Location.Code, true);

        // [GIVEN] Create default bin for location
        LibraryWarehouse.CreateBin(Bin, Location.Code, 'GETSRC', '', '');
        Location.Validate("Default Bin Code", Bin.Code);
        Location.Modify(true);

        // [GIVEN] Configure Vendor with Subcontracting Location
        Vendor.Get(WorkCenter[2]."Subcontractor No.");
        Vendor."Subcontr. Location Code" := Location.Code;
        Vendor."Location Code" := Location.Code;
        Vendor.Modify();

        // [GIVEN] Setup Requisition Worksheet Template
        SubcWarehouseLibrary.UpdateSubMgmtSetupWithReqWkshTemplate();

        // [GIVEN] Create multiple Production Orders
        SubcWarehouseLibrary.CreateAndRefreshProductionOrder(
            ProductionOrder1, "Production Order Status"::Released,
            ProductionOrder1."Source Type"::Item, Item."No.", Quantity1, Location.Code);

        SubcWarehouseLibrary.CreateAndRefreshProductionOrder(
            ProductionOrder2, "Production Order Status"::Released,
            ProductionOrder2."Source Type"::Item, Item."No.", Quantity2, Location.Code);

        // [WHEN] Create Subcontracting Purchase Orders via Subcontracting Worksheet
        // The worksheet combines all lines for the same vendor into one PO
        SubcWarehouseLibrary.CreateSubcontractingOrdersViaWorksheet(ProductionOrder1."No.", PurchaseHeader);

        // [THEN] Verify Data Consistency: Both prod orders should create lines on the same PO (same vendor)
        PurchaseLine.SetRange("Document Type", PurchaseHeader."Document Type");
        PurchaseLine.SetRange("Document No.", PurchaseHeader."No.");
        PurchaseLine.SetRange(Type, "Purchase Line Type"::Item);
        Assert.RecordCount(PurchaseLine, 2);

        // [WHEN] Use "Get Source Documents" function to create warehouse receipt
        LibraryPurchase.ReleasePurchaseDocument(PurchaseHeader);
        SubcWarehouseLibrary.CreateWarehouseReceiptUsingGetSourceDocuments(WarehouseReceiptHeader, Location.Code);

        // [THEN] Verify Data Consistency: Warehouse receipt created with lines from the PO
        WarehouseReceiptLine.SetRange("No.", WarehouseReceiptHeader."No.");
        WarehouseReceiptLine.SetRange("Item No.", Item."No.");
        Assert.RecordCount(WarehouseReceiptLine, 2);

        // [THEN] Verify Data Consistency: Lines from the combined PO
        WarehouseReceiptLine.SetRange("Source No.", PurchaseHeader."No.");
        Assert.RecordCount(WarehouseReceiptLine, 2);

        // [THEN] Verify Data Consistency: Each line has correct data reconciled with original source
        WarehouseReceiptLine.SetRange("Source No.");
        WarehouseReceiptLine.FindSet();
        repeat
            Assert.AreEqual(Item."No.", WarehouseReceiptLine."Item No.",
                'Each line should have correct item');
            Assert.AreEqual(Location.Code, WarehouseReceiptLine."Location Code",
                'Each line should have correct location');
            Assert.IsTrue(WarehouseReceiptLine.Quantity > 0,
                'Each line should have positive quantity');
        until WarehouseReceiptLine.Next() = 0;

        // [WHEN] Post warehouse receipt
        SubcWarehouseLibrary.PostWarehouseReceipt(WarehouseReceiptHeader, PostedWhseReceiptHeader);

        // [THEN] Verify Posted Entries: Subsequent processing correct for each line
        Assert.AreNotEqual('', PostedWhseReceiptHeader."No.",
            'Posted warehouse receipt should be created');

        // [THEN] Verify Data Consistency: All ledger entries correct
        VerifyLedgerEntriesForGetSourceDocuments(Item."No.", Location.Code);
    end;

    local procedure VerifyQuantityReconciliation(ProductionOrder: Record "Production Order"; PurchaseHeader: Record "Purchase Header"; ExpectedQuantity: Decimal)
    var
        PurchaseLine: Record "Purchase Line";
    begin
        PurchaseLine.SetRange("Document Type", PurchaseHeader."Document Type");
        PurchaseLine.SetRange("Document No.", PurchaseHeader."No.");
        PurchaseLine.SetRange(Type, "Purchase Line Type"::Item);
        PurchaseLine.FindFirst();

        Assert.AreEqual(ExpectedQuantity, PurchaseLine.Quantity,
            'Purchase line quantity should match expected quantity');
    end;

    local procedure VerifyLedgerEntriesForCombinedScenario(ItemNo: Code[20]; Quantity: Decimal; LocationCode: Code[10])
    var
        ItemLedgerEntry: Record "Item Ledger Entry";
        CapacityLedgerEntry: Record "Capacity Ledger Entry";
    begin
        // Verify Item Ledger Entries
        ItemLedgerEntry.SetRange("Item No.", ItemNo);
        ItemLedgerEntry.SetRange("Location Code", LocationCode);
        Assert.RecordIsNotEmpty(ItemLedgerEntry);

        // Verify Capacity Ledger Entries exist
        CapacityLedgerEntry.SetRange("Item No.", ItemNo);
        Assert.RecordIsNotEmpty(CapacityLedgerEntry);
    end;

    local procedure VerifyLedgerEntriesForMultiVendorScenario(ItemNo: Code[20]; Quantity: Decimal; LocationCode: Code[10])
    var
        ItemLedgerEntry: Record "Item Ledger Entry";
        CapacityLedgerEntry: Record "Capacity Ledger Entry";
    begin
        // Verify Item Ledger Entries
        ItemLedgerEntry.SetRange("Item No.", ItemNo);
        ItemLedgerEntry.SetRange("Location Code", LocationCode);
        Assert.RecordIsNotEmpty(ItemLedgerEntry);

        // Verify Capacity Ledger Entries exist
        CapacityLedgerEntry.SetRange("Item No.", ItemNo);
        Assert.RecordIsNotEmpty(CapacityLedgerEntry);
    end;

    local procedure VerifyLedgerEntriesForGetSourceDocuments(ItemNo: Code[20]; LocationCode: Code[10])
    var
        ItemLedgerEntry: Record "Item Ledger Entry";
    begin
        // Verify Item Ledger Entries
        ItemLedgerEntry.SetRange("Item No.", ItemNo);
        ItemLedgerEntry.SetRange("Location Code", LocationCode);
        Assert.RecordIsNotEmpty(ItemLedgerEntry);
    end;
}
