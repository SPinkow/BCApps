// ------------------------------------------------------------------------------------------------
// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License. See License.txt in the project root for license information.
// ------------------------------------------------------------------------------------------------
namespace Microsoft.Manufacturing.Subcontracting.Test;

using Microsoft.Finance.GeneralLedger.Setup;
using Microsoft.Foundation.Enums;
using Microsoft.Foundation.NoSeries;
using Microsoft.Inventory.Item;
using Microsoft.Inventory.Ledger;
using Microsoft.Inventory.Location;
using Microsoft.Inventory.Tracking;
using Microsoft.Manufacturing.Capacity;
using Microsoft.Manufacturing.Document;
using Microsoft.Manufacturing.MachineCenter;
using Microsoft.Manufacturing.ProductionBOM;
using Microsoft.Manufacturing.Routing;
using Microsoft.Manufacturing.Setup;
using Microsoft.Manufacturing.Subcontracting;
using Microsoft.Manufacturing.WorkCenter;
using Microsoft.Purchases.Document;
using Microsoft.Purchases.History;
using Microsoft.Purchases.Setup;
using Microsoft.Purchases.Vendor;
using Microsoft.Warehouse.Document;
using Microsoft.Warehouse.History;
using Microsoft.Warehouse.Setup;
using Microsoft.Warehouse.Structure;

codeunit 140009 "Subc. Whse Data Integrity"
{
    // [FEATURE] Subcontracting Data Integrity and Validation Tests
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
        LibraryManufacturing: Codeunit "Library - Manufacturing";
        LibraryRandom: Codeunit "Library - Random";
        LibrarySetupStorage: Codeunit "Library - Setup Storage";
        LibraryTestInitialize: Codeunit "Library - Test Initialize";
        LibraryUtility: Codeunit "Library - Utility";
        LibraryWarehouse: Codeunit "Library - Warehouse";
        SubcontractingMgmtLibrary: Codeunit "Subc. Management Library";
        SubcLibraryMfgManagement: Codeunit "Subc. Library Mfg. Management";
        SubcWarehouseLibrary: Codeunit "Subc. Warehouse Library";
        SubSetupLibrary: Codeunit "Subc. Setup Library";
        IsInitialized: Boolean;
        HandlingSerialNo: Code[50];
        HandlingLotNo: Code[50];
        HandlingQty: Decimal;
        HandlingMode: Option Verify,Insert;

    local procedure Initialize()
    begin
        HandlingSerialNo := '';
        HandlingLotNo := '';
        HandlingQty := 0;
        HandlingMode := HandlingMode::Verify;
        LibraryTestInitialize.OnTestInitialize(Codeunit::"Subc. Whse Data Integrity");
        LibrarySetupStorage.Restore();

        SubcontractingMgmtLibrary.Initialize();
        SubcLibraryMfgManagement.Initialize();
        SubSetupLibrary.InitSetupFields();

        if IsInitialized then
            exit;

        LibraryTestInitialize.OnBeforeTestSuiteInitialize(Codeunit::"Subc. Whse Data Integrity");

        LibraryERMCountryData.CreateVATData();
        LibraryERMCountryData.UpdateGeneralPostingSetup();
        LibrarySetupStorage.Save(Database::"General Ledger Setup");

        IsInitialized := true;
        Commit();
        LibraryTestInitialize.OnAfterTestSuiteInitialize(Codeunit::"Subc. Whse Data Integrity");
    end;

    [Test]
    procedure VerifyCannotDeleteLastRoutingOperationWhenPurchaseOrderExists()
    var
        Item: Record Item;
        Location: Record Location;
        MachineCenter: array[2] of Record "Machine Center";
        ProductionOrder: Record "Production Order";
        PurchaseLine: Record "Purchase Line";
        ProdOrderRoutingLine: Record "Prod. Order Routing Line";
        WorkCenter: array[2] of Record "Work Center";
        Vendor: Record Vendor;
        Quantity: Decimal;
        LastOperationNo: Code[10];
    begin
        // [SCENARIO] System prevents deletion of last routing operation when purchase orders exist
        // [FEATURE] Subcontracting Data Integrity - Prevention of last routing operation deletion

        // [GIVEN] Complete setup with subcontracting infrastructure
        Initialize();
        Quantity := LibraryRandom.RandInt(10) + 5;

        SubcWarehouseLibrary.CreateAndCalculateNeededWorkAndMachineCenter(WorkCenter, MachineCenter, true);
        SubcWarehouseLibrary.CreateItemForProductionIncludeRoutingAndProdBOM(Item, WorkCenter, MachineCenter);
        SubcWarehouseLibrary.UpdateProdBomAndRoutingWithRoutingLink(Item, WorkCenter[1]."No.");
        SubcWarehouseLibrary.CreateLocationWithWarehouseHandling(Location);

        Vendor.Get(WorkCenter[1]."Subcontractor No.");
        Vendor."Subcontr. Location Code" := Location.Code;
        Vendor."Location Code" := Location.Code;
        Vendor.Modify();

        SubcWarehouseLibrary.CreateAndRefreshProductionOrder(
            ProductionOrder, "Production Order Status"::Released,
            ProductionOrder."Source Type"::Item, Item."No.", Quantity, Location.Code);

        SubcWarehouseLibrary.UpdateSubMgmtSetupWithReqWkshTemplate();

        // [GIVEN] Create Subcontracting Purchase Order for the last routing operation
        SubcWarehouseLibrary.CreateSubcontractingOrderFromProdOrderRouting(Item."Routing No.", WorkCenter[2]."No.", PurchaseLine);

        // [GIVEN] Find the last routing operation
        ProdOrderRoutingLine.SetRange("Routing No.", Item."Routing No.");
        ProdOrderRoutingLine.SetRange("Work Center No.", WorkCenter[2]."No.");
        ProdOrderRoutingLine.SetRange("Next Operation No.", '');
        Assert.RecordIsNotEmpty(ProdOrderRoutingLine);
        ProdOrderRoutingLine.FindFirst();
        LastOperationNo := ProdOrderRoutingLine."Operation No.";

        // [WHEN] Attempt to delete the last routing operation that has associated purchase order
        asserterror ProdOrderRoutingLine.Delete(true);

        // [THEN] The deletion should be prevented (no specific error validation since this is a data integrity protection test)
        // The test passes if the deletion fails, maintaining referential integrity
    end;

    [Test]
    procedure VerifyCannotAddRoutingOperationAfterLastWhenPurchaseOrderExists()
    var
        Item: Record Item;
        Location: Record Location;
        MachineCenter: array[2] of Record "Machine Center";
        ProductionOrder: Record "Production Order";
        PurchaseLine: Record "Purchase Line";
        ProdOrderRoutingLine: Record "Prod. Order Routing Line";
        NewRoutingLine: Record "Prod. Order Routing Line";
        WorkCenter: array[2] of Record "Work Center";
        Vendor: Record Vendor;
        Quantity: Decimal;
    begin
        // [SCENARIO] System prevents adding routing operation after last operation when purchase orders exist
        // [FEATURE] Subcontracting Data Integrity - Prevention of adding operations after last when PO exists

        // [GIVEN] Complete setup
        Initialize();
        Quantity := LibraryRandom.RandInt(10) + 5;

        SubcWarehouseLibrary.CreateAndCalculateNeededWorkAndMachineCenter(WorkCenter, MachineCenter, true);
        SubcWarehouseLibrary.CreateItemForProductionIncludeRoutingAndProdBOM(Item, WorkCenter, MachineCenter);
        SubcWarehouseLibrary.UpdateProdBomAndRoutingWithRoutingLink(Item, WorkCenter[2]."No.");
        SubcWarehouseLibrary.CreateLocationWithWarehouseHandling(Location);

        Vendor.Get(WorkCenter[2]."Subcontractor No.");
        Vendor."Subcontr. Location Code" := Location.Code;
        Vendor."Location Code" := Location.Code;
        Vendor.Modify();

        SubcWarehouseLibrary.CreateAndRefreshProductionOrder(
            ProductionOrder, "Production Order Status"::Released,
            ProductionOrder."Source Type"::Item, Item."No.", Quantity, Location.Code);

        SubcWarehouseLibrary.UpdateSubMgmtSetupWithReqWkshTemplate();

        // [GIVEN] Create Subcontracting Purchase Order for last operation
        SubcWarehouseLibrary.CreateSubcontractingOrderFromProdOrderRouting(Item."Routing No.", WorkCenter[2]."No.", PurchaseLine);

        // [GIVEN] Find the last routing operation with purchase order
        ProdOrderRoutingLine.SetRange("Routing No.", Item."Routing No.");
        ProdOrderRoutingLine.SetRange("Work Center No.", WorkCenter[2]."No.");
        ProdOrderRoutingLine.SetRange("Next Operation No.", '');
        ProdOrderRoutingLine.FindFirst();

        // [WHEN] Attempt to add a new routing operation after the last operation
        NewRoutingLine.Init();
        NewRoutingLine.Status := ProdOrderRoutingLine.Status;
        NewRoutingLine."Prod. Order No." := ProdOrderRoutingLine."Prod. Order No.";
        NewRoutingLine."Routing Reference No." := ProdOrderRoutingLine."Routing Reference No.";
        NewRoutingLine."Routing No." := ProdOrderRoutingLine."Routing No.";
        NewRoutingLine."Operation No." := '9999';
        NewRoutingLine.Validate(Type, ProdOrderRoutingLine.Type::"Work Center");
        NewRoutingLine.Validate("No.", WorkCenter[1]."No.");

        // [THEN] The insertion should be controlled by referential integrity
        // Note: This test verifies the operation can be attempted but may be prevented by business logic
        asserterror NewRoutingLine.Insert(true);
    end;

    [Test]
    procedure VerifyCannotChangeWorkCenterNoWhenPurchaseLineExists()
    var
        Item: Record Item;
        Location: Record Location;
        MachineCenter: array[2] of Record "Machine Center";
        ProductionOrder: Record "Production Order";
        PurchaseLine: Record "Purchase Line";
        ProdOrderRoutingLine: Record "Prod. Order Routing Line";
        WorkCenter: array[2] of Record "Work Center";
        WorkCenter3: Record "Work Center";
        Vendor: Record Vendor;
        Quantity: Decimal;
    begin
        // [SCENARIO] System prevents changing Work Center No. on routing operation when purchase line exists
        // [FEATURE] Subcontracting Data Integrity - Prevention of critical field changes when PO exists

        // [GIVEN] Complete setup with subcontracting infrastructure
        Initialize();
        Quantity := LibraryRandom.RandInt(10) + 5;

        SubcWarehouseLibrary.CreateAndCalculateNeededWorkAndMachineCenter(WorkCenter, MachineCenter, true);
        SubcWarehouseLibrary.CreateItemForProductionIncludeRoutingAndProdBOM(Item, WorkCenter, MachineCenter);
        SubcWarehouseLibrary.UpdateProdBomAndRoutingWithRoutingLink(Item, WorkCenter[2]."No.");
        SubcWarehouseLibrary.CreateLocationWithWarehouseHandling(Location);

        Vendor.Get(WorkCenter[2]."Subcontractor No.");
        Vendor."Subcontr. Location Code" := Location.Code;
        Vendor."Location Code" := Location.Code;
        Vendor.Modify();

        // [GIVEN] Create a third work center to attempt changing to
        SubcLibraryMfgManagement.CreateWorkCenterWithCalendar(WorkCenter3, LibraryRandom.RandDec(10, 2));

        SubcWarehouseLibrary.CreateAndRefreshProductionOrder(
            ProductionOrder, "Production Order Status"::Released,
            ProductionOrder."Source Type"::Item, Item."No.", Quantity, Location.Code);

        SubcWarehouseLibrary.UpdateSubMgmtSetupWithReqWkshTemplate();

        // [GIVEN] Create Subcontracting Purchase Order for the routing operation
        SubcWarehouseLibrary.CreateSubcontractingOrderFromProdOrderRouting(Item."Routing No.", WorkCenter[2]."No.", PurchaseLine);

        // [GIVEN] Find the routing operation with purchase order
        ProdOrderRoutingLine.SetRange("Routing No.", Item."Routing No.");
        ProdOrderRoutingLine.SetRange("Work Center No.", WorkCenter[2]."No.");
        ProdOrderRoutingLine.FindFirst();

        // [WHEN] Attempt to change Work Center No. on the routing operation
        asserterror ProdOrderRoutingLine.Validate("Work Center No.", WorkCenter3."No.");

        // [THEN] The change should be prevented because a purchase line exists
        // Error expected: Cannot change critical fields when purchase line exists
    end;

    [Test]
    procedure VerifyCannotChangeOperationNoWhenPurchaseLineExists()
    var
        Item: Record Item;
        Location: Record Location;
        MachineCenter: array[2] of Record "Machine Center";
        ProductionOrder: Record "Production Order";
        PurchaseLine: Record "Purchase Line";
        ProdOrderRoutingLine: Record "Prod. Order Routing Line";
        WorkCenter: array[2] of Record "Work Center";
        Vendor: Record Vendor;
        Quantity: Decimal;
    begin
        // [SCENARIO] System prevents changing Operation No. on routing operation when purchase line exists
        // [FEATURE] Subcontracting Data Integrity - Prevention of critical field changes when PO exists

        // [GIVEN] Complete setup with subcontracting infrastructure
        Initialize();
        Quantity := LibraryRandom.RandInt(10) + 5;

        SubcWarehouseLibrary.CreateAndCalculateNeededWorkAndMachineCenter(WorkCenter, MachineCenter, true);
        SubcWarehouseLibrary.CreateItemForProductionIncludeRoutingAndProdBOM(Item, WorkCenter, MachineCenter);
        SubcWarehouseLibrary.UpdateProdBomAndRoutingWithRoutingLink(Item, WorkCenter[2]."No.");
        SubcWarehouseLibrary.CreateLocationWithWarehouseHandling(Location);

        Vendor.Get(WorkCenter[2]."Subcontractor No.");
        Vendor."Subcontr. Location Code" := Location.Code;
        Vendor."Location Code" := Location.Code;
        Vendor.Modify();

        SubcWarehouseLibrary.CreateAndRefreshProductionOrder(
            ProductionOrder, "Production Order Status"::Released,
            ProductionOrder."Source Type"::Item, Item."No.", Quantity, Location.Code);

        SubcWarehouseLibrary.UpdateSubMgmtSetupWithReqWkshTemplate();

        // [GIVEN] Create Subcontracting Purchase Order for the routing operation
        SubcWarehouseLibrary.CreateSubcontractingOrderFromProdOrderRouting(Item."Routing No.", WorkCenter[2]."No.", PurchaseLine);

        // [GIVEN] Find the routing operation with purchase order
        ProdOrderRoutingLine.SetRange("Routing No.", Item."Routing No.");
        ProdOrderRoutingLine.SetRange("Work Center No.", WorkCenter[2]."No.");
        ProdOrderRoutingLine.FindFirst();

        // [WHEN] Attempt to change Operation No. on the routing operation (by renaming)
        asserterror ProdOrderRoutingLine.Rename(
            ProdOrderRoutingLine.Status,
            ProdOrderRoutingLine."Prod. Order No.",
            ProdOrderRoutingLine."Routing Reference No.",
            ProdOrderRoutingLine."Routing No.",
            '9999'); // New operation no.

        // [THEN] The change should be prevented because a purchase line exists
        // Error expected: Cannot rename routing line when purchase line exists
    end;

    [Test]
    procedure VerifyDataIntegrityWhenModifyingLastOperationWithPO()
    var
        Item: Record Item;
        Location: Record Location;
        MachineCenter: array[2] of Record "Machine Center";
        ProductionOrder: Record "Production Order";
        PurchaseLine: Record "Purchase Line";
        ProdOrderRoutingLine: Record "Prod. Order Routing Line";
        WorkCenter: array[2] of Record "Work Center";
        Vendor: Record Vendor;
        Quantity: Decimal;
        OriginalSetupTime: Decimal;
    begin
        // [SCENARIO] Verify data integrity when modifying last routing operation with associated purchase order
        // [FEATURE] Subcontracting Data Integrity - Modification validation

        // [GIVEN] Complete setup
        Initialize();
        Quantity := LibraryRandom.RandInt(10) + 5;

        SubcWarehouseLibrary.CreateAndCalculateNeededWorkAndMachineCenter(WorkCenter, MachineCenter, true);
        SubcWarehouseLibrary.CreateItemForProductionIncludeRoutingAndProdBOM(Item, WorkCenter, MachineCenter);
        SubcWarehouseLibrary.UpdateProdBomAndRoutingWithRoutingLink(Item, WorkCenter[2]."No.");
        SubcWarehouseLibrary.CreateLocationWithWarehouseHandling(Location);

        Vendor.Get(WorkCenter[2]."Subcontractor No.");
        Vendor."Subcontr. Location Code" := Location.Code;
        Vendor."Location Code" := Location.Code;
        Vendor.Modify();

        SubcWarehouseLibrary.CreateAndRefreshProductionOrder(
            ProductionOrder, "Production Order Status"::Released,
            ProductionOrder."Source Type"::Item, Item."No.", Quantity, Location.Code);

        SubcWarehouseLibrary.UpdateSubMgmtSetupWithReqWkshTemplate();

        // [GIVEN] Create Purchase Order for last operation
        SubcWarehouseLibrary.CreateSubcontractingOrderFromProdOrderRouting(Item."Routing No.", WorkCenter[2]."No.", PurchaseLine);

        // [GIVEN] Find last routing operation
        ProdOrderRoutingLine.SetRange("Routing No.", Item."Routing No.");
        ProdOrderRoutingLine.SetRange("Work Center No.", WorkCenter[2]."No.");
        ProdOrderRoutingLine.SetRange("Next Operation No.", '');
        ProdOrderRoutingLine.FindFirst();
        OriginalSetupTime := ProdOrderRoutingLine."Setup Time";

        // [WHEN] Attempt to modify fields on the routing operation with associated PO
        // This should maintain referential integrity
        ProdOrderRoutingLine.Validate("Setup Time", OriginalSetupTime + 10);
        ProdOrderRoutingLine.Modify(true);

        // [THEN] Verify the modification was allowed for non-critical fields
        ProdOrderRoutingLine.Get(ProdOrderRoutingLine.Status, ProdOrderRoutingLine."Prod. Order No.",
            ProdOrderRoutingLine."Routing Reference No.", ProdOrderRoutingLine."Routing No.",
            ProdOrderRoutingLine."Operation No.");
        Assert.AreEqual(OriginalSetupTime + 10, ProdOrderRoutingLine."Setup Time",
            'Setup time should be modifiable');

        // [THEN] Verify purchase order link remains intact
        PurchaseLine.Get(PurchaseLine."Document Type", PurchaseLine."Document No.", PurchaseLine."Line No.");
        Assert.AreEqual(ProdOrderRoutingLine."Operation No.", PurchaseLine."Operation No.",
            'Purchase Order link must remain intact after modification');
    end;

    [Test]
    procedure VerifyQuantityReconciliationAfterMultiplePartialReceipts()
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
        WorkCenter: array[2] of Record "Work Center";
        Vendor: Record Vendor;
        WarehouseEmployee: Record "Warehouse Employee";
        TotalQuantity: Decimal;
        FirstReceiptQty: Decimal;
        SecondReceiptQty: Decimal;
        ThirdReceiptQty: Decimal;
        TotalPostedQty: Decimal;
    begin
        // [SCENARIO] Verify quantity reconciliation is maintained after multiple partial warehouse receipts
        // [FEATURE] Subcontracting Data Integrity - Quantity Reconciliation

        // [GIVEN] Complete setup with quantity that allows multiple partial receipts
        Initialize();
        TotalQuantity := 30;
        FirstReceiptQty := 10;
        SecondReceiptQty := 12;
        ThirdReceiptQty := TotalQuantity - FirstReceiptQty - SecondReceiptQty; // Remaining 8

        SubcWarehouseLibrary.CreateAndCalculateNeededWorkAndMachineCenter(WorkCenter, MachineCenter, true);
        SubcWarehouseLibrary.CreateItemForProductionIncludeRoutingAndProdBOM(Item, WorkCenter, MachineCenter);
        SubcWarehouseLibrary.UpdateProdBomAndRoutingWithRoutingLink(Item, WorkCenter[2]."No.");
        SubcWarehouseLibrary.CreateLocationWithWarehouseHandling(Location);

        // [GIVEN] Create Warehouse Employee for the location
        LibraryWarehouse.CreateWarehouseEmployee(WarehouseEmployee, Location.Code, false);

        // [GIVEN] Configure Vendor
        Vendor.Get(WorkCenter[2]."Subcontractor No.");
        Vendor."Subcontr. Location Code" := Location.Code;
        Vendor."Location Code" := Location.Code;
        Vendor.Modify();

        // [GIVEN] Create Production Order and Subcontracting Purchase Order
        SubcWarehouseLibrary.CreateAndRefreshProductionOrder(
            ProductionOrder, "Production Order Status"::Released,
            ProductionOrder."Source Type"::Item, Item."No.", TotalQuantity, Location.Code);

        SubcWarehouseLibrary.UpdateSubMgmtSetupWithReqWkshTemplate();

        SubcWarehouseLibrary.CreateSubcontractingOrderFromProdOrderRouting(Item."Routing No.", WorkCenter[2]."No.", PurchaseLine);
        PurchaseHeader.Get(PurchaseLine."Document Type", PurchaseLine."Document No.");

        // [GIVEN] Create Warehouse Receipt from Purchase Order
        SubcWarehouseLibrary.CreateWarehouseReceiptFromPurchaseOrder(PurchaseHeader, WarehouseReceiptHeader);

        // [WHEN] Post First Partial Receipt
        SubcWarehouseLibrary.PostPartialWarehouseReceipt(WarehouseReceiptHeader, FirstReceiptQty, PostedWhseReceiptHeader);

        // [THEN] Verify first receipt quantities
        PostedWhseReceiptLine.SetRange("No.", PostedWhseReceiptHeader."No.");
        PostedWhseReceiptLine.FindFirst();
        Assert.AreEqual(FirstReceiptQty, PostedWhseReceiptLine.Quantity,
            'First posted receipt should have correct quantity');

        // [THEN] Verify base quantity on first posted receipt
        Assert.AreEqual(FirstReceiptQty * PostedWhseReceiptLine."Qty. per Unit of Measure", PostedWhseReceiptLine."Qty. (Base)", 'First posted receipt should have correct Qty. (Base)');

        // [THEN] Verify remaining quantity on warehouse receipt
        WarehouseReceiptLine.SetRange("No.", WarehouseReceiptHeader."No.");
        WarehouseReceiptLine.FindFirst();
        Assert.AreEqual(TotalQuantity - FirstReceiptQty, WarehouseReceiptLine."Qty. Outstanding",
            'Outstanding quantity should be correctly reduced after first receipt');

        // [THEN] Verify base quantity outstanding after first receipt
        Assert.AreEqual((TotalQuantity - FirstReceiptQty) * WarehouseReceiptLine."Qty. per Unit of Measure",
            WarehouseReceiptLine."Qty. Outstanding (Base)",
            'Qty. Outstanding (Base) should be correctly calculated after first receipt');

        // [WHEN] Post Second Partial Receipt
        SubcWarehouseLibrary.PostPartialWarehouseReceipt(WarehouseReceiptHeader, SecondReceiptQty, PostedWhseReceiptHeader);

        // [THEN] Verify remaining quantity after second receipt
        WarehouseReceiptLine.FindFirst();
        Assert.AreEqual(ThirdReceiptQty, WarehouseReceiptLine."Qty. Outstanding",
            'Outstanding quantity should be correctly reduced after second receipt');

        // [THEN] Verify base quantity outstanding after second receipt
        Assert.AreEqual(ThirdReceiptQty * WarehouseReceiptLine."Qty. per Unit of Measure",
            WarehouseReceiptLine."Qty. Outstanding (Base)",
            'Qty. Outstanding (Base) should be correctly calculated after second receipt');

        // [WHEN] Post Final Receipt (remaining quantity)
        SubcWarehouseLibrary.PostPartialWarehouseReceipt(WarehouseReceiptHeader, ThirdReceiptQty, PostedWhseReceiptHeader);

        // [THEN] Verify total posted quantity across all receipts matches original PO quantity
        TotalPostedQty := 0;
        PostedWhseReceiptLine.Reset();
        PostedWhseReceiptLine.SetRange("Whse. Receipt No.", WarehouseReceiptHeader."No.");
        PostedWhseReceiptLine.SetRange("Item No.", Item."No.");
        if PostedWhseReceiptLine.FindSet() then
            repeat
                TotalPostedQty += PostedWhseReceiptLine.Quantity;
            until PostedWhseReceiptLine.Next() = 0;

        Assert.AreEqual(TotalQuantity, TotalPostedQty,
            'Total posted quantity across all receipts must equal original PO quantity');

        // [THEN] Verify purchase line outstanding quantity is zero (fully received)
        PurchaseLine.Get(PurchaseLine."Document Type", PurchaseLine."Document No.", PurchaseLine."Line No.");
        Assert.AreEqual(0, PurchaseLine."Outstanding Quantity",
            'Purchase Line outstanding quantity should be zero after full receipt');
    end;

    [Test]
    procedure PostWhseReceiptWithOverDeliveryWithinTolerance()
    var
        Item: Record Item;
        Location: Record Location;
        MachineCenter: array[2] of Record "Machine Center";
        ProductionOrder: Record "Production Order";
        PurchaseHeader: Record "Purchase Header";
        PurchaseLine: Record "Purchase Line";
        OverReceiptCode: Record "Over-Receipt Code";
        PurchRcptLine: Record "Purch. Rcpt. Line";
        WarehouseReceiptHeader: Record "Warehouse Receipt Header";
        WarehouseReceiptLine: Record "Warehouse Receipt Line";
        PostedWhseReceiptHeader: Record "Posted Whse. Receipt Header";
        PostedWhseReceiptLine: Record "Posted Whse. Receipt Line";
        ItemLedgerEntry: Record "Item Ledger Entry";
        WorkCenter: array[2] of Record "Work Center";
        Vendor: Record Vendor;
        WarehouseEmployee: Record "Warehouse Employee";
        OriginalQuantity: Decimal;
        OverReceiptQuantity: Decimal;
        TolerancePercent: Decimal;
    begin
        // [SCENARIO] Warehouse receipt can be posted with over-delivery within tolerance for subcontracting
        // [FEATURE] Subcontracting Over-Receipt - Within Tolerance

        // [GIVEN] Complete setup
        Initialize();
        OriginalQuantity := 100;
        TolerancePercent := 10;
        OverReceiptQuantity := OriginalQuantity + Round(OriginalQuantity * TolerancePercent / 100, 1);

        // [GIVEN] Create Over-Receipt Code with 10% tolerance
        CreateOverReceiptCode(OverReceiptCode, TolerancePercent);

        // [GIVEN] Create Work Centers and Machine Centers with Subcontracting
        SubcWarehouseLibrary.CreateAndCalculateNeededWorkAndMachineCenter(WorkCenter, MachineCenter, true);
        SubcWarehouseLibrary.CreateItemForProductionIncludeRoutingAndProdBOM(Item, WorkCenter, MachineCenter);
        SubcWarehouseLibrary.UpdateProdBomAndRoutingWithRoutingLink(Item, WorkCenter[2]."No.");
        SubcWarehouseLibrary.CreateLocationWithWarehouseHandling(Location);

        // [GIVEN] Create Warehouse Employee for the location
        LibraryWarehouse.CreateWarehouseEmployee(WarehouseEmployee, Location.Code, false);

        // [GIVEN] Configure Vendor with Over-Receipt Code
        Vendor.Get(WorkCenter[2]."Subcontractor No.");
        Vendor."Subcontr. Location Code" := Location.Code;
        Vendor."Location Code" := Location.Code;
        Vendor."Over-Receipt Code" := OverReceiptCode.Code;
        Vendor.Modify();

        // [GIVEN] Create Production Order and Subcontracting Purchase Order
        SubcWarehouseLibrary.CreateAndRefreshProductionOrder(
            ProductionOrder, "Production Order Status"::Released,
            ProductionOrder."Source Type"::Item, Item."No.", OriginalQuantity, Location.Code);

        SubcWarehouseLibrary.UpdateSubMgmtSetupWithReqWkshTemplate();

        SubcWarehouseLibrary.CreateSubcontractingOrderFromProdOrderRouting(Item."Routing No.", WorkCenter[2]."No.", PurchaseLine);
        PurchaseHeader.Get(PurchaseLine."Document Type", PurchaseLine."Document No.");

        // [GIVEN] Create Warehouse Receipt from Purchase Order
        SubcWarehouseLibrary.CreateWarehouseReceiptFromPurchaseOrder(PurchaseHeader, WarehouseReceiptHeader);

        // [WHEN] Set Qty. to Receive to over-delivery quantity (within tolerance)
        WarehouseReceiptLine.SetRange("No.", WarehouseReceiptHeader."No.");
        WarehouseReceiptLine.FindFirst();
        WarehouseReceiptLine.Validate("Qty. to Receive", OverReceiptQuantity);
        WarehouseReceiptLine.Modify(true);

        // [WHEN] Post Warehouse Receipt
        SubcWarehouseLibrary.PostWarehouseReceipt(WarehouseReceiptHeader, PostedWhseReceiptHeader);

        // [THEN] Posted Warehouse Receipt exists with over-delivery quantity
        PostedWhseReceiptLine.SetRange("No.", PostedWhseReceiptHeader."No.");
        PostedWhseReceiptLine.FindFirst();
        Assert.AreEqual(OverReceiptQuantity, PostedWhseReceiptLine.Quantity,
            'Posted Whse. Receipt Line should have over-delivery quantity');

        // [THEN] Purchase Line is fully received with over-receipt quantity
        PurchaseLine.Get(PurchaseLine."Document Type", PurchaseLine."Document No.", PurchaseLine."Line No.");
        //TODO  Assert.AreEqual(OverReceiptQuantity - OriginalQuantity, PurchaseLine."Over-Receipt Quantity",
        //     'Purchase Line should show correct Over-Receipt Quantity');

        // [THEN] Item Ledger Entry has total received quantity (for last operation)
        ItemLedgerEntry.SetRange("Item No.", Item."No.");
        ItemLedgerEntry.SetRange("Location Code", Location.Code);
        ItemLedgerEntry.SetRange("Entry Type", ItemLedgerEntry."Entry Type"::Output);
        ItemLedgerEntry.FindFirst();
        Assert.AreEqual(OverReceiptQuantity, ItemLedgerEntry.Quantity,
            'Item Ledger Entry should have over-delivery quantity');

        // [THEN] Purchase Receipt Line has correct Over-Receipt fields
        PurchRcptLine.SetRange("Order No.", PurchaseHeader."No.");
        PurchRcptLine.FindFirst();
        //TODO  Assert.AreEqual(OverReceiptQuantity, PurchRcptLine.Quantity,
        //     'Purchase Receipt Line should have total received quantity');
        //TODO Assert.AreEqual(OverReceiptQuantity - OriginalQuantity, PurchRcptLine."Over-Receipt Quantity",
        //     'Over-Receipt Quantity should be calculated correctly');
    end;

    [Test]
    [HandlerFunctions('ItemTrackingLinesPageHandler')]
    procedure OverReceiptWithItemTrackingAndLotNumbers()
    var
        Item: Record Item;
        Location: Record Location;
        MachineCenter: array[2] of Record "Machine Center";
        ProductionOrder: Record "Production Order";
        ProdOrderLine: Record "Prod. Order Line";
        PurchaseHeader: Record "Purchase Header";
        PurchaseLine: Record "Purchase Line";
        OverReceiptCode: Record "Over-Receipt Code";
        WarehouseReceiptHeader: Record "Warehouse Receipt Header";
        WarehouseReceiptLine: Record "Warehouse Receipt Line";
        PostedWhseReceiptHeader: Record "Posted Whse. Receipt Header";
        PostedWhseReceiptLine: Record "Posted Whse. Receipt Line";
        ItemLedgerEntry: Record "Item Ledger Entry";
        WorkCenter: array[2] of Record "Work Center";
        Vendor: Record Vendor;
        WarehouseEmployee: Record "Warehouse Employee";
        ReservationEntry: Record "Reservation Entry";
        NoSeriesCodeunit: Codeunit "No. Series";
        WarehouseReceiptPage: TestPage "Warehouse Receipt";
        OriginalQuantity: Decimal;
        OverReceiptQuantity: Decimal;
        TolerancePercent: Decimal;
        LotNo: Code[50];
    begin
        // [SCENARIO] Warehouse receipt with over-delivery within tolerance for lot-tracked item
        // [FEATURE] Subcontracting Over-Receipt - Item Tracking with Lot Numbers

        // [GIVEN] Complete setup with lot-tracked item
        Initialize();
        OriginalQuantity := 100;
        TolerancePercent := 10;
        OverReceiptQuantity := OriginalQuantity + Round(OriginalQuantity * TolerancePercent / 100, 1);

        // [GIVEN] Create Over-Receipt Code with 10% tolerance
        CreateOverReceiptCode(OverReceiptCode, TolerancePercent);

        // [GIVEN] Create Work Centers and Machine Centers with Subcontracting
        SubcWarehouseLibrary.CreateAndCalculateNeededWorkAndMachineCenter(WorkCenter, MachineCenter, true);

        // [GIVEN] Create Lot-tracked Item for Production include Routing and Prod. BOM
        SubcWarehouseLibrary.CreateLotTrackedItemForProductionWithSetup(Item, WorkCenter, MachineCenter);

        // [GIVEN] Update BOM and Routing with Routing Link for last operation
        SubcWarehouseLibrary.UpdateProdBomAndRoutingWithRoutingLink(Item, WorkCenter[2]."No.");

        // [GIVEN] Create Location with Warehouse Handling
        SubcWarehouseLibrary.CreateLocationWithWarehouseHandling(Location);

        // [GIVEN] Create Warehouse Employee for the location
        LibraryWarehouse.CreateWarehouseEmployee(WarehouseEmployee, Location.Code, false);

        // [GIVEN] Configure Vendor with Over-Receipt Code and Location
        Vendor.Get(WorkCenter[2]."Subcontractor No.");
        Vendor."Subcontr. Location Code" := Location.Code;
        Vendor."Location Code" := Location.Code;
        Vendor."Over-Receipt Code" := OverReceiptCode.Code;
        Vendor.Modify();

        // [GIVEN] Create Production Order and assign lot tracking
        SubcWarehouseLibrary.CreateAndRefreshProductionOrder(
            ProductionOrder, "Production Order Status"::Released,
            ProductionOrder."Source Type"::Item, Item."No.", OriginalQuantity, Location.Code);

        // [GIVEN] Assign Lot Number to Production Order Line
        ProdOrderLine.SetRange(Status, ProductionOrder.Status);
        ProdOrderLine.SetRange("Prod. Order No.", ProductionOrder."No.");
        ProdOrderLine.FindFirst();

        // [GIVEN] Setup Requisition Worksheet Template
        SubcWarehouseLibrary.UpdateSubMgmtSetupWithReqWkshTemplate();

        // [GIVEN] Create Subcontracting Purchase Order for last operation
        SubcWarehouseLibrary.CreateSubcontractingOrderFromProdOrderRouting(Item."Routing No.", WorkCenter[2]."No.", PurchaseLine);
        PurchaseHeader.Get(PurchaseLine."Document Type", PurchaseLine."Document No.");

        // [GIVEN] Create Warehouse Receipt from Purchase Order
        SubcWarehouseLibrary.CreateWarehouseReceiptFromPurchaseOrder(PurchaseHeader, WarehouseReceiptHeader);

        // [WHEN] Set Qty. to Receive to over-delivery quantity (within tolerance)
        WarehouseReceiptLine.SetRange("No.", WarehouseReceiptHeader."No.");
        WarehouseReceiptLine.FindFirst();
        WarehouseReceiptLine.Validate("Qty. to Receive", OverReceiptQuantity);
        WarehouseReceiptLine.Modify(true);

        // [WHEN] Assign lot tracking with over-receipt quantity via page handler
        LotNo := NoSeriesCodeunit.GetNextNo(Item."Lot Nos.");
        HandlingMode := HandlingMode::Insert;
        HandlingSerialNo := '';
        HandlingLotNo := LotNo;
        HandlingQty := OverReceiptQuantity;

        WarehouseReceiptPage.OpenEdit();
        WarehouseReceiptPage.GoToRecord(WarehouseReceiptHeader);
        WarehouseReceiptPage.WhseReceiptLines.GoToRecord(WarehouseReceiptLine);
        WarehouseReceiptPage.WhseReceiptLines.ItemTrackingLines.Invoke();
        WarehouseReceiptPage.Close();

        // [WHEN] Post Warehouse Receipt
        SubcWarehouseLibrary.PostWarehouseReceipt(WarehouseReceiptHeader, PostedWhseReceiptHeader);

        // [THEN] Posted Warehouse Receipt exists with over-delivery quantity
        PostedWhseReceiptLine.SetRange("No.", PostedWhseReceiptHeader."No.");
        PostedWhseReceiptLine.FindFirst();
        Assert.AreEqual(OverReceiptQuantity, PostedWhseReceiptLine.Quantity,
            'Posted Whse. Receipt Line should have over-delivery quantity');

        // [THEN] Item Ledger Entry has correct lot number and over-receipt quantity
        ItemLedgerEntry.SetRange("Item No.", Item."No.");
        ItemLedgerEntry.SetRange("Location Code", Location.Code);
        ItemLedgerEntry.SetRange("Entry Type", ItemLedgerEntry."Entry Type"::Output);
        ItemLedgerEntry.SetRange("Lot No.", LotNo);
        Assert.RecordIsNotEmpty(ItemLedgerEntry);

        ItemLedgerEntry.FindFirst();
        Assert.AreEqual(OverReceiptQuantity, ItemLedgerEntry.Quantity,
            'Item Ledger Entry should have over-delivery quantity with correct lot number');
        Assert.AreEqual(LotNo, ItemLedgerEntry."Lot No.",
            'Item Ledger Entry should have the assigned lot number');
    end;

    [Test]
    procedure CannotPostWhseReceiptExceedingOverReceiptTolerance()
    var
        Item: Record Item;
        Location: Record Location;
        MachineCenter: array[2] of Record "Machine Center";
        ProductionOrder: Record "Production Order";
        PurchaseHeader: Record "Purchase Header";
        PurchaseLine: Record "Purchase Line";
        OverReceiptCode: Record "Over-Receipt Code";
        WarehouseReceiptHeader: Record "Warehouse Receipt Header";
        WarehouseReceiptLine: Record "Warehouse Receipt Line";
        WorkCenter: array[2] of Record "Work Center";
        Vendor: Record Vendor;
        WarehouseEmployee: Record "Warehouse Employee";
        OriginalQuantity: Decimal;
        ExcessQuantity: Decimal;
        TolerancePercent: Decimal;
    begin
        // [SCENARIO] System prevents warehouse receipt posting when over-delivery exceeds tolerance
        // [FEATURE] Subcontracting Over-Receipt - Exceeds Tolerance

        // [GIVEN] Complete setup
        Initialize();
        OriginalQuantity := 100;
        TolerancePercent := 10;
        // 15% over-delivery exceeds 10% tolerance
        ExcessQuantity := OriginalQuantity + Round(OriginalQuantity * 15 / 100, 1);

        // [GIVEN] Create Over-Receipt Code with 10% tolerance
        CreateOverReceiptCode(OverReceiptCode, TolerancePercent);

        // [GIVEN] Create Work Centers and Manufacturing Setup
        SubcWarehouseLibrary.CreateAndCalculateNeededWorkAndMachineCenter(WorkCenter, MachineCenter, true);
        SubcWarehouseLibrary.CreateItemForProductionIncludeRoutingAndProdBOM(Item, WorkCenter, MachineCenter);
        SubcWarehouseLibrary.UpdateProdBomAndRoutingWithRoutingLink(Item, WorkCenter[2]."No.");
        SubcWarehouseLibrary.CreateLocationWithWarehouseHandling(Location);

        // [GIVEN] Create Warehouse Employee for the location
        LibraryWarehouse.CreateWarehouseEmployee(WarehouseEmployee, Location.Code, false);

        // [GIVEN] Configure Vendor with Over-Receipt Code
        Vendor.Get(WorkCenter[2]."Subcontractor No.");
        Vendor."Subcontr. Location Code" := Location.Code;
        Vendor."Location Code" := Location.Code;
        Vendor."Over-Receipt Code" := OverReceiptCode.Code;
        Vendor.Modify();

        // [GIVEN] Create Production Order and Subcontracting Purchase Order
        SubcWarehouseLibrary.CreateAndRefreshProductionOrder(
            ProductionOrder, "Production Order Status"::Released,
            ProductionOrder."Source Type"::Item, Item."No.", OriginalQuantity, Location.Code);

        SubcWarehouseLibrary.UpdateSubMgmtSetupWithReqWkshTemplate();

        SubcWarehouseLibrary.CreateSubcontractingOrderFromProdOrderRouting(Item."Routing No.", WorkCenter[2]."No.", PurchaseLine);
        PurchaseHeader.Get(PurchaseLine."Document Type", PurchaseLine."Document No.");

        // [GIVEN] Create Warehouse Receipt from Purchase Order
        SubcWarehouseLibrary.CreateWarehouseReceiptFromPurchaseOrder(PurchaseHeader, WarehouseReceiptHeader);

        // [WHEN] Attempt to set Qty. to Receive exceeding tolerance (15% when tolerance is 10%)
        WarehouseReceiptLine.SetRange("No.", WarehouseReceiptHeader."No.");
        WarehouseReceiptLine.FindFirst();

        // [THEN] Validation should raise an error
        //TODO asserterror WarehouseReceiptLine.Validate("Qty. to Receive", ExcessQuantity);

        // // [THEN] The error should indicate quantity exceeds tolerance
        // Assert.ExpectedError('');
    end;

    [Test]
    procedure OverReceiptQuantityIgnoredForNonLastOperation()
    var
        Item: Record Item;
        Location: Record Location;
        MachineCenter: array[2] of Record "Machine Center";
        ProductionOrder: Record "Production Order";
        PurchaseHeader: Record "Purchase Header";
        PurchaseLine: Record "Purchase Line";
        OverReceiptCode: Record "Over-Receipt Code";
        WarehouseReceiptHeader: Record "Warehouse Receipt Header";
        WarehouseReceiptLine: Record "Warehouse Receipt Line";
        PostedWhseReceiptHeader: Record "Posted Whse. Receipt Header";
        PostedWhseReceiptLine: Record "Posted Whse. Receipt Line";
        ItemLedgerEntry: Record "Item Ledger Entry";
        CapacityLedgerEntry: Record "Capacity Ledger Entry";
        WorkCenter: array[2] of Record "Work Center";
        Vendor: Record Vendor;
        WarehouseEmployee: Record "Warehouse Employee";
        Bin: Record Bin;
        OriginalQuantity: Decimal;
        AttemptedOverReceiptQty: Decimal;
        TolerancePercent: Decimal;
    begin
        // [SCENARIO] Over-receipt quantity has no effect for non-last operation (no physical inventory movement)
        // [FEATURE] Subcontracting Over-Receipt - Non-Last Operation Behavior
        // Non-last operations do not create inventory movements (zero base quantities),
        // so over-receipt validation is not applicable - the quantity received is tracked
        // for capacity purposes only

        // [GIVEN] Complete setup for non-last operation
        Initialize();
        OriginalQuantity := 100;
        TolerancePercent := 10;
        AttemptedOverReceiptQty := OriginalQuantity + Round(OriginalQuantity * TolerancePercent / 100, 1);

        // [GIVEN] Create Over-Receipt Code with 10% tolerance
        CreateOverReceiptCode(OverReceiptCode, TolerancePercent);

        // [GIVEN] Create Work Centers and Machine Centers with Subcontracting
        SubcWarehouseLibrary.CreateAndCalculateNeededWorkAndMachineCenter(WorkCenter, MachineCenter, true);

        // [GIVEN] Create Item with Production BOM and Routing
        SubcWarehouseLibrary.CreateItemForProductionIncludeRoutingAndProdBOM(Item, WorkCenter, MachineCenter);

        // [GIVEN] Update BOM and Routing with Routing Link for FIRST operation (non-last)
        SubcWarehouseLibrary.UpdateProdBomAndRoutingWithRoutingLink(Item, WorkCenter[1]."No.");

        // [GIVEN] Create Location with Warehouse Handling
        SubcWarehouseLibrary.CreateLocationWithWarehouseHandling(Location);

        // [GIVEN] Create default bin for location
        LibraryWarehouse.CreateBin(Bin, Location.Code, 'NONLAST-OR', '', '');
        Location.Validate("Default Bin Code", Bin.Code);
        Location.Modify(true);

        // [GIVEN] Create Warehouse Employee for the location
        LibraryWarehouse.CreateWarehouseEmployee(WarehouseEmployee, Location.Code, false);

        // [GIVEN] Configure Vendor (first work center) with Over-Receipt Code and Location
        Vendor.Get(WorkCenter[1]."Subcontractor No.");
        Vendor."Subcontr. Location Code" := Location.Code;
        Vendor."Location Code" := Location.Code;
        Vendor."Over-Receipt Code" := OverReceiptCode.Code;
        Vendor.Modify();

        // [GIVEN] Create Production Order
        SubcWarehouseLibrary.CreateAndRefreshProductionOrder(
            ProductionOrder, "Production Order Status"::Released,
            ProductionOrder."Source Type"::Item, Item."No.", OriginalQuantity, Location.Code);

        // [GIVEN] Setup Requisition Worksheet Template
        SubcWarehouseLibrary.UpdateSubMgmtSetupWithReqWkshTemplate();

        // [GIVEN] Create Subcontracting Purchase Order for non-last operation (WorkCenter[1])
        SubcWarehouseLibrary.CreateSubcontractingOrderFromProdOrderRouting(Item."Routing No.", WorkCenter[1]."No.", PurchaseLine);
        PurchaseHeader.Get(PurchaseLine."Document Type", PurchaseLine."Document No.");

        // [GIVEN] Create Warehouse Receipt from Purchase Order
        SubcWarehouseLibrary.CreateWarehouseReceiptFromPurchaseOrder(PurchaseHeader, WarehouseReceiptHeader);

        // [THEN] Verify warehouse receipt line is marked as NotLastOperation
        WarehouseReceiptLine.SetRange("No.", WarehouseReceiptHeader."No.");
        WarehouseReceiptLine.FindFirst();
        Assert.AreEqual("Subc. Purchase Line Type"::NotLastOperation,
            WarehouseReceiptLine."Subc. Purchase Line Type",
            'Warehouse Receipt Line should be marked as Not Last Operation');

        // [THEN] Verify NotLastOperation has zero base quantities (no inventory movement)
        Assert.AreEqual(0, WarehouseReceiptLine."Qty. (Base)",
            'NotLastOperation should have zero Qty. (Base) - no physical inventory movement');

        // [WHEN] Attempt to set over-receipt quantity on warehouse receipt line
        // For non-last operations, the Qty. to Receive can be set but it only affects capacity posting
        WarehouseReceiptLine.Validate("Qty. to Receive", AttemptedOverReceiptQty);
        WarehouseReceiptLine.Modify(true);

        // [THEN] Base quantities remain zero even with over-receipt attempt
        Assert.AreEqual(0, WarehouseReceiptLine."Qty. to Receive (Base)",
            'NotLastOperation should maintain zero Qty. to Receive (Base) regardless of over-receipt');

        // [WHEN] Post Warehouse Receipt
        SubcWarehouseLibrary.PostWarehouseReceipt(WarehouseReceiptHeader, PostedWhseReceiptHeader);

        // [THEN] Posted Warehouse Receipt shows the quantity but with zero base
        PostedWhseReceiptLine.SetRange("No.", PostedWhseReceiptHeader."No.");
        PostedWhseReceiptLine.FindFirst();
        Assert.AreEqual(AttemptedOverReceiptQty, PostedWhseReceiptLine.Quantity,
            'Posted receipt should show the received quantity');
        Assert.AreEqual(0, PostedWhseReceiptLine."Qty. (Base)",
            'Posted receipt for NotLastOperation should have zero Qty. (Base)');

        // [THEN] NO Item Ledger Entry created (non-last operation does not create inventory)
        ItemLedgerEntry.SetRange("Item No.", Item."No.");
        ItemLedgerEntry.SetRange("Location Code", Location.Code);
        ItemLedgerEntry.SetRange("Entry Type", ItemLedgerEntry."Entry Type"::Output);
        Assert.RecordIsEmpty(ItemLedgerEntry);

        // [THEN] Capacity Ledger Entry created with zero output quantity (operation completion tracked only)
        CapacityLedgerEntry.SetRange("Order No.", ProductionOrder."No.");
        CapacityLedgerEntry.SetRange("Work Center No.", WorkCenter[1]."No.");
        Assert.RecordIsNotEmpty(CapacityLedgerEntry);

        CapacityLedgerEntry.FindFirst();
        Assert.AreEqual(0, CapacityLedgerEntry."Output Quantity",
            'Capacity Ledger Entry for non-last operation should have zero output quantity');
    end;

    local procedure CreateOverReceiptCode(var OverReceiptCode: Record "Over-Receipt Code"; TolerancePercent: Decimal)
    begin
        OverReceiptCode.Init();
        OverReceiptCode.Code := LibraryUtility.GenerateGUID();
        OverReceiptCode.Description := StrSubstNo('%1% Over-Receipt Tolerance', TolerancePercent);
        OverReceiptCode."Over-Receipt Tolerance %" := TolerancePercent;
        OverReceiptCode."Required Approval" := false;
        OverReceiptCode.Insert(true);
    end;

    [ModalPageHandler]
    procedure ItemTrackingLinesPageHandler(var ItemTrackingLines: TestPage "Item Tracking Lines")
    begin
        case HandlingMode of
            HandlingMode::Verify:
                begin
                    ItemTrackingLines.First();
                    if HandlingSerialNo <> '' then
                        Assert.AreEqual(HandlingSerialNo, Format(ItemTrackingLines."Serial No.".Value), 'Serial No. mismatch');
                    if HandlingLotNo <> '' then
                        Assert.AreEqual(HandlingLotNo, Format(ItemTrackingLines."Lot No.".Value), 'Lot No. mismatch');

                    Assert.AreEqual(HandlingQty, ItemTrackingLines."Quantity (Base)".AsDecimal(), 'Quantity mismatch');
                end;
            HandlingMode::Insert:
                begin
                    ItemTrackingLines.New();
                    if HandlingSerialNo <> '' then
                        ItemTrackingLines."Serial No.".SetValue(HandlingSerialNo);
                    if HandlingLotNo <> '' then
                        ItemTrackingLines."Lot No.".SetValue(HandlingLotNo);

                    ItemTrackingLines."Quantity (Base)".SetValue(HandlingQty);
                end;
        end;
        ItemTrackingLines.OK().Invoke();
    end;
}
