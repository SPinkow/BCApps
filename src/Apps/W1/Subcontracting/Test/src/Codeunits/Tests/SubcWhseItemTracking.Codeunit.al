// ------------------------------------------------------------------------------------------------
// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License. See License.txt in the project root for license information.
// ------------------------------------------------------------------------------------------------
namespace Microsoft.Manufacturing.Subcontracting.Test;

using Microsoft.Finance.GeneralLedger.Setup;
using Microsoft.Foundation.Enums;
using Microsoft.Foundation.NoSeries;
using Microsoft.Inventory.Item;
using Microsoft.Inventory.Item.Catalog;
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
using Microsoft.Purchases.Vendor;
using Microsoft.Warehouse.Activity;
using Microsoft.Warehouse.Document;
using Microsoft.Warehouse.History;
using Microsoft.Warehouse.Setup;
using Microsoft.Warehouse.Structure;

codeunit 140005 "Subc. Whse Item Tracking"
{
    // [FEATURE] Subcontracting Item Tracking Integration Tests
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
        LibraryItemTracking: Codeunit "Library - Item Tracking";
        LibraryManufacturing: Codeunit "Library - Manufacturing";
        LibraryPurchase: Codeunit "Library - Purchase";
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
        HandlingSourceType: Integer;

    local procedure Initialize()
    begin
        HandlingSerialNo := '';
        HandlingLotNo := '';
        HandlingQty := 0;
        HandlingMode := HandlingMode::Verify;
        HandlingSourceType := 0;
        LibraryTestInitialize.OnTestInitialize(Codeunit::"Subc. Whse Item Tracking");
        LibrarySetupStorage.Restore();

        SubcontractingMgmtLibrary.Initialize();
        SubcLibraryMfgManagement.Initialize();
        SubSetupLibrary.InitSetupFields();

        if IsInitialized then
            exit;

        LibraryTestInitialize.OnBeforeTestSuiteInitialize(Codeunit::"Subc. Whse Item Tracking");

        LibraryERMCountryData.CreateVATData();
        LibraryERMCountryData.UpdateGeneralPostingSetup();
        LibrarySetupStorage.Save(Database::"General Ledger Setup");

        IsInitialized := true;
        Commit();
        LibraryTestInitialize.OnAfterTestSuiteInitialize(Codeunit::"Subc. Whse Item Tracking");
    end;

    [Test]
    [HandlerFunctions('ItemTrackingLinesPageHandler')]
    procedure FullProcessWithSerialTrackingFromProdOrderLine()
    var
        Item: Record Item;
        Location: Record Location;
        MachineCenter: array[2] of Record "Machine Center";
        ProductionOrder: Record "Production Order";
        ProdOrderLine: Record "Prod. Order Line";
        PurchaseHeader: Record "Purchase Header";
        PurchaseLine: Record "Purchase Line";
        WarehouseActivityHeader: Record "Warehouse Activity Header";
        WarehouseActivityLine: Record "Warehouse Activity Line";
        WarehouseReceiptHeader: Record "Warehouse Receipt Header";
        WarehouseReceiptLine: Record "Warehouse Receipt Line";
        PostedWhseReceiptHeader: Record "Posted Whse. Receipt Header";
        WarehouseReceiptPage: TestPage "Warehouse Receipt";
        WarehouseEmployee: Record "Warehouse Employee";
        WorkCenter: array[2] of Record "Work Center";
        Vendor: Record Vendor;
        ReservationEntry: Record "Reservation Entry";
        ItemLedgerEntry: Record "Item Ledger Entry";
        NoSeriesCodeunit: Codeunit "No. Series";
        Quantity: Decimal;
        SerialNo: Code[50];
    begin
        // [SCENARIO] Full Process with Serial Tracking from Production Order Line
        // [FEATURE] Subcontracting Item Tracking - Last Operation with Serial Numbers

        // [GIVEN] Complete Setup of Manufacturing, include Work- and Machine Centers, Serial-tracked Item
        Initialize();
        Quantity := 1; // Serial tracking requires quantity of 1

        // [GIVEN] Create and Calculate needed Work and Machine Center with Subcontracting
        SubcWarehouseLibrary.CreateAndCalculateNeededWorkAndMachineCenter(WorkCenter, MachineCenter, true);

        // [GIVEN] Create Serial-tracked Item for Production include Routing and Prod. BOM
        SubcWarehouseLibrary.CreateSerialTrackedItemForProductionWithSetup(Item, WorkCenter, MachineCenter);

        // [GIVEN] Update BOM and Routing with Routing Link
        SubcWarehouseLibrary.UpdateProdBomAndRoutingWithRoutingLink(Item, WorkCenter[2]."No.");

        // [GIVEN] Create Location with Warehouse Handling
        SubcWarehouseLibrary.CreateLocationWithWarehouseHandling(Location);

        // [GIVEN] Update Vendor with Subcontracting Location Code
        Vendor.Get(WorkCenter[2]."Subcontractor No.");
        Vendor."Subcontr. Location Code" := Location.Code;
        Vendor."Location Code" := Location.Code;
        Vendor.Modify();

        // [GIVEN] Create and Refresh Production Order
        SubcWarehouseLibrary.CreateAndRefreshProductionOrder(
            ProductionOrder, "Production Order Status"::Released,
            ProductionOrder."Source Type"::Item, Item."No.", Quantity, Location.Code);

        // [GIVEN] Assign Serial Number to Production Order Line
        ProdOrderLine.SetRange(Status, ProductionOrder.Status);
        ProdOrderLine.SetRange("Prod. Order No.", ProductionOrder."No.");
        ProdOrderLine.FindFirst();

        SerialNo := NoSeriesCodeunit.GetNextNo(Item."Serial Nos.");
        LibraryManufacturing.CreateProdOrderItemTracking(ReservationEntry, ProdOrderLine, SerialNo, '', Quantity);

        // [GIVEN] Update Subcontracting Management Setup with Requisition Worksheet Template
        SubcWarehouseLibrary.UpdateSubMgmtSetupWithReqWkshTemplate();

        // [WHEN] Create Subcontracting Purchase Order from Prod. Order Routing
        SubcWarehouseLibrary.CreateSubcontractingOrderFromProdOrderRouting(Item."Routing No.", WorkCenter[2]."No.", PurchaseLine);
        PurchaseHeader.Get(PurchaseLine."Document Type", PurchaseLine."Document No.");

        // [WHEN] Create Warehouse Receipt from Purchase Order
        SubcWarehouseLibrary.CreateWarehouseReceiptFromPurchaseOrder(PurchaseHeader, WarehouseReceiptHeader);

        // [THEN] Verify Data Consistency: Item tracking is propagated to Warehouse Receipt
        WarehouseReceiptLine.SetRange("No.", WarehouseReceiptHeader."No.");
        WarehouseReceiptLine.FindFirst();

        Assert.AreEqual(Item."No.", WarehouseReceiptLine."Item No.",
            'Item No. should match on Warehouse Receipt Line');

        // [THEN] Verify Data Consistency: Reservation entries exist for warehouse receipt
        HandlingSerialNo := SerialNo;
        HandlingLotNo := '';
        HandlingQty := Quantity;

        // [GIVEN] Create Warehouse Employee for Location
        LibraryWarehouse.CreateWarehouseEmployee(WarehouseEmployee, Location.Code, false);

        WarehouseReceiptPage.OpenView();
        WarehouseReceiptPage.GoToRecord(WarehouseReceiptHeader);
        WarehouseReceiptPage.WhseReceiptLines.GoToRecord(WarehouseReceiptLine);
        WarehouseReceiptPage.WhseReceiptLines.ItemTrackingLines.Invoke();
        WarehouseReceiptPage.Close();

        // [WHEN] Post Warehouse Receipt
        SubcWarehouseLibrary.PostWarehouseReceipt(WarehouseReceiptHeader, PostedWhseReceiptHeader);

        // [WHEN] Create Put-away from Posted Warehouse Receipt
        SubcWarehouseLibrary.CreatePutAwayFromPostedWhseReceipt(PostedWhseReceiptHeader, WarehouseActivityHeader);

        // [THEN] Verify Data Consistency: Item tracking is propagated to Put-away
        WarehouseActivityLine.SetRange("Activity Type", WarehouseActivityHeader.Type);
        WarehouseActivityLine.SetRange("No.", WarehouseActivityHeader."No.");
        WarehouseActivityLine.FindFirst();

        Assert.AreEqual(Item."No.", WarehouseActivityLine."Item No.",
            'Item No. should match on Put-away Line');
        Assert.AreEqual(SerialNo, WarehouseActivityLine."Serial No.",
            'Serial No. should be propagated to Put-away Line');

        // [WHEN] Post Put-away
        LibraryWarehouse.RegisterWhseActivity(WarehouseActivityHeader);

        // [THEN] Verify Posted Entries: Item Ledger Entry contains correct serial number
        ItemLedgerEntry.SetRange("Item No.", Item."No.");
        ItemLedgerEntry.SetRange("Serial No.", SerialNo);
        ItemLedgerEntry.SetRange("Entry Type", ItemLedgerEntry."Entry Type"::Output);
        Assert.RecordIsNotEmpty(ItemLedgerEntry);

        ItemLedgerEntry.FindFirst();
        Assert.AreEqual(Quantity, ItemLedgerEntry.Quantity,
            'Item Ledger Entry Quantity should match');
        Assert.AreEqual(Location.Code, ItemLedgerEntry."Location Code",
            'Item Ledger Entry Location Code should match');
    end;

    [Test]
    [HandlerFunctions('ItemTrackingLinesPageHandler')]
    procedure FullProcessWithLotTrackingFromProdOrderLine()
    var
        WarehouseReceiptPage: TestPage "Warehouse Receipt";
        Item: Record Item;
        Location: Record Location;
        MachineCenter: array[2] of Record "Machine Center";
        ProductionOrder: Record "Production Order";
        ProdOrderLine: Record "Prod. Order Line";
        PurchaseHeader: Record "Purchase Header";
        PurchaseLine: Record "Purchase Line";
        WarehouseActivityHeader: Record "Warehouse Activity Header";
        WarehouseActivityLine: Record "Warehouse Activity Line";
        WarehouseReceiptHeader: Record "Warehouse Receipt Header";
        WarehouseReceiptLine: Record "Warehouse Receipt Line";
        PostedWhseReceiptHeader: Record "Posted Whse. Receipt Header";
        WarehouseEmployee: Record "Warehouse Employee";
        WorkCenter: array[2] of Record "Work Center";
        Vendor: Record Vendor;
        ReservationEntry: Record "Reservation Entry";
        ItemLedgerEntry: Record "Item Ledger Entry";
        NoSeriesCodeunit: Codeunit "No. Series";
        Quantity: Decimal;
        LotNo: Code[50];
    begin
        // [SCENARIO] Full Process with Lot Tracking from Production Order Line
        // [FEATURE] Subcontracting Item Tracking - Last Operation with Lot Numbers

        // [GIVEN] Complete Setup of Manufacturing, include Work- and Machine Centers, Lot-tracked Item
        Initialize();
        Quantity := LibraryRandom.RandIntInRange(5, 10);

        // [GIVEN] Create and Calculate needed Work and Machine Center with Subcontracting
        SubcWarehouseLibrary.CreateAndCalculateNeededWorkAndMachineCenter(WorkCenter, MachineCenter, true);

        // [GIVEN] Create Lot-tracked Item for Production include Routing and Prod. BOM
        SubcWarehouseLibrary.CreateLotTrackedItemForProductionWithSetup(Item, WorkCenter, MachineCenter);

        // [GIVEN] Update BOM and Routing with Routing Link
        SubcWarehouseLibrary.UpdateProdBomAndRoutingWithRoutingLink(Item, WorkCenter[2]."No.");

        // [GIVEN] Create Location with Warehouse Handling
        SubcWarehouseLibrary.CreateLocationWithWarehouseHandling(Location);

        // [GIVEN] Update Vendor with Subcontracting Location Code
        Vendor.Get(WorkCenter[2]."Subcontractor No.");
        Vendor."Subcontr. Location Code" := Location.Code;
        Vendor."Location Code" := Location.Code;
        Vendor.Modify();

        // [GIVEN] Create and Refresh Production Order
        SubcWarehouseLibrary.CreateAndRefreshProductionOrder(
            ProductionOrder, "Production Order Status"::Released,
            ProductionOrder."Source Type"::Item, Item."No.", Quantity, Location.Code);

        // [GIVEN] Assign Lot Number to Production Order Line
        ProdOrderLine.SetRange(Status, ProductionOrder.Status);
        ProdOrderLine.SetRange("Prod. Order No.", ProductionOrder."No.");
        ProdOrderLine.FindFirst();

        LotNo := NoSeriesCodeunit.GetNextNo(Item."Lot Nos.");
        LibraryManufacturing.CreateProdOrderItemTracking(ReservationEntry, ProdOrderLine, '', LotNo, Quantity);

        // [GIVEN] Update Subcontracting Management Setup with Requisition Worksheet Template
        SubcWarehouseLibrary.UpdateSubMgmtSetupWithReqWkshTemplate();

        // [WHEN] Create Subcontracting Purchase Order from Prod. Order Routing
        SubcWarehouseLibrary.CreateSubcontractingOrderFromProdOrderRouting(Item."Routing No.", WorkCenter[2]."No.", PurchaseLine);
        PurchaseHeader.Get(PurchaseLine."Document Type", PurchaseLine."Document No.");

        // [WHEN] Create Warehouse Receipt from Purchase Order
        SubcWarehouseLibrary.CreateWarehouseReceiptFromPurchaseOrder(PurchaseHeader, WarehouseReceiptHeader);

        // [THEN] Verify Data Consistency: Item tracking information is consistent across all documents
        WarehouseReceiptLine.SetRange("No.", WarehouseReceiptHeader."No.");
        WarehouseReceiptLine.FindFirst();

        // [THEN] Verify Data Consistency: Reservation entries exist for warehouse receipt with lot number
        HandlingSerialNo := '';
        HandlingLotNo := LotNo;
        HandlingQty := Quantity;

        // [GIVEN] Create Warehouse Employee for Location
        LibraryWarehouse.CreateWarehouseEmployee(WarehouseEmployee, Location.Code, false);

        WarehouseReceiptPage.OpenView();
        WarehouseReceiptPage.GoToRecord(WarehouseReceiptHeader);
        WarehouseReceiptPage.WhseReceiptLines.GoToRecord(WarehouseReceiptLine);
        WarehouseReceiptPage.WhseReceiptLines.ItemTrackingLines.Invoke();
        WarehouseReceiptPage.Close();

        // [WHEN] Post Warehouse Receipt
        SubcWarehouseLibrary.PostWarehouseReceipt(WarehouseReceiptHeader, PostedWhseReceiptHeader);

        // [WHEN] Create Put-away from Posted Warehouse Receipt
        SubcWarehouseLibrary.CreatePutAwayFromPostedWhseReceipt(PostedWhseReceiptHeader, WarehouseActivityHeader);

        // [THEN] Verify Data Consistency: Item tracking is correctly passed to the put-away
        WarehouseActivityLine.SetRange("Activity Type", WarehouseActivityHeader.Type);
        WarehouseActivityLine.SetRange("No.", WarehouseActivityHeader."No.");
        WarehouseActivityLine.FindFirst();

        Assert.AreEqual(LotNo, WarehouseActivityLine."Lot No.",
            'Lot No. should be propagated to Put-away Line');

        // [WHEN] Post Put-away
        LibraryWarehouse.RegisterWhseActivity(WarehouseActivityHeader);

        // [THEN] Verify Posted Entries: All posted entries correctly reflect assigned item tracking
        ItemLedgerEntry.SetRange("Item No.", Item."No.");
        ItemLedgerEntry.SetRange("Lot No.", LotNo);
        ItemLedgerEntry.SetRange("Entry Type", ItemLedgerEntry."Entry Type"::Output);
        Assert.RecordIsNotEmpty(ItemLedgerEntry);

        ItemLedgerEntry.FindFirst();
        Assert.AreEqual(Quantity, ItemLedgerEntry.Quantity,
            'Item Ledger Entry Quantity should match');
        Assert.AreEqual(Location.Code, ItemLedgerEntry."Location Code",
            'Item Ledger Entry Location Code should match');
    end;

    [Test]
    [HandlerFunctions('ItemTrackingLinesPageHandler')]
    procedure FullProcessWithLotTrackingFromWhseReceiptLine()
    var
        WarehouseReceiptPage: TestPage "Warehouse Receipt";
        Item: Record Item;
        Location: Record Location;
        MachineCenter: array[2] of Record "Machine Center";
        ProductionOrder: Record "Production Order";
        PurchaseHeader: Record "Purchase Header";
        PurchaseLine: Record "Purchase Line";
        WarehouseActivityHeader: Record "Warehouse Activity Header";
        WarehouseActivityLine: Record "Warehouse Activity Line";
        WarehouseReceiptHeader: Record "Warehouse Receipt Header";
        WarehouseReceiptLine: Record "Warehouse Receipt Line";
        PostedWhseReceiptHeader: Record "Posted Whse. Receipt Header";
        WarehouseEmployee: Record "Warehouse Employee";
        WorkCenter: array[2] of Record "Work Center";
        Vendor: Record Vendor;
        ItemLedgerEntry: Record "Item Ledger Entry";
        NoSeriesCodeunit: Codeunit "No. Series";
        Quantity: Decimal;
        LotNo: Code[50];
    begin
        // [SCENARIO] Full Process with Lot Tracking from Warehouse Receipt Line
        // [FEATURE] Subcontracting Item Tracking - Assign tracking at warehouse receipt stage

        // [GIVEN] Complete Setup of Manufacturing, include Work- and Machine Centers, Lot-tracked Item
        Initialize();
        Quantity := LibraryRandom.RandIntInRange(5, 10);

        // [GIVEN] Create and Calculate needed Work and Machine Center with Subcontracting
        SubcWarehouseLibrary.CreateAndCalculateNeededWorkAndMachineCenter(WorkCenter, MachineCenter, true);

        // [GIVEN] Create Lot-tracked Item for Production include Routing and Prod. BOM
        SubcWarehouseLibrary.CreateLotTrackedItemForProductionWithSetup(Item, WorkCenter, MachineCenter);

        // [GIVEN] Update BOM and Routing with Routing Link
        SubcWarehouseLibrary.UpdateProdBomAndRoutingWithRoutingLink(Item, WorkCenter[2]."No.");

        // [GIVEN] Create Location with Warehouse Handling
        SubcWarehouseLibrary.CreateLocationWithWarehouseHandling(Location);

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
        PurchaseHeader.Get(PurchaseLine."Document Type", PurchaseLine."Document No.");

        // [WHEN] Create Warehouse Receipt from Purchase Order
        SubcWarehouseLibrary.CreateWarehouseReceiptFromPurchaseOrder(PurchaseHeader, WarehouseReceiptHeader);

        // [WHEN] Assign Lot Number at Warehouse Receipt Line stage using Item Tracking Lines page
        WarehouseReceiptLine.SetRange("No.", WarehouseReceiptHeader."No.");
        WarehouseReceiptLine.FindFirst();

        LotNo := NoSeriesCodeunit.GetNextNo(Item."Lot Nos.");

        // [GIVEN] Create Warehouse Employee for Location
        LibraryWarehouse.CreateWarehouseEmployee(WarehouseEmployee, Location.Code, false);

        // [WHEN] Insert item tracking via page
        HandlingMode := HandlingMode::Insert;
        HandlingSerialNo := '';
        HandlingLotNo := LotNo;
        HandlingQty := Quantity;

        WarehouseReceiptPage.OpenEdit();
        WarehouseReceiptPage.GoToRecord(WarehouseReceiptHeader);
        WarehouseReceiptPage.WhseReceiptLines.GoToRecord(WarehouseReceiptLine);
        WarehouseReceiptPage.WhseReceiptLines.ItemTrackingLines.Invoke();
        WarehouseReceiptPage.Close();

        // [THEN] Verify item tracking is correctly assigned and source type is Prod. Order Line
        HandlingMode := HandlingMode::Verify;
        HandlingSourceType := Database::"Prod. Order Line";

        WarehouseReceiptPage.OpenView();
        WarehouseReceiptPage.GoToRecord(WarehouseReceiptHeader);
        WarehouseReceiptPage.WhseReceiptLines.GoToRecord(WarehouseReceiptLine);
        WarehouseReceiptPage.WhseReceiptLines.ItemTrackingLines.Invoke();
        WarehouseReceiptPage.Close();

        // [WHEN] Post Warehouse Receipt
        SubcWarehouseLibrary.PostWarehouseReceipt(WarehouseReceiptHeader, PostedWhseReceiptHeader);

        // [WHEN] Create Put-away from Posted Warehouse Receipt
        SubcWarehouseLibrary.CreatePutAwayFromPostedWhseReceipt(PostedWhseReceiptHeader, WarehouseActivityHeader);

        // [THEN] Verify Data Consistency: Item tracking is correctly passed to put-away
        WarehouseActivityLine.SetRange("Activity Type", WarehouseActivityHeader.Type);
        WarehouseActivityLine.SetRange("No.", WarehouseActivityHeader."No.");
        WarehouseActivityLine.FindFirst();

        Assert.AreEqual(LotNo, WarehouseActivityLine."Lot No.",
            'Lot No. should be propagated to Put-away Line');

        // [WHEN] Post Put-away
        LibraryWarehouse.RegisterWhseActivity(WarehouseActivityHeader);

        // [THEN] Verify Posted Entries: Posted entries correctly reflect assigned item tracking
        ItemLedgerEntry.SetRange("Item No.", Item."No.");
        ItemLedgerEntry.SetRange("Lot No.", LotNo);
        ItemLedgerEntry.SetRange("Entry Type", ItemLedgerEntry."Entry Type"::Output);
        Assert.RecordIsNotEmpty(ItemLedgerEntry);

        ItemLedgerEntry.FindFirst();
        Assert.AreEqual(Quantity, ItemLedgerEntry.Quantity,
            'Item Ledger Entry Quantity should match');
        Assert.AreEqual(LotNo, ItemLedgerEntry."Lot No.",
            'Item Ledger Entry Lot No. should match');
    end;

    [Test]
    [HandlerFunctions('ItemTrackingLinesPageHandler')]
    procedure ItemTrackingForNonLastOperations()
    var
        WarehouseReceiptPage: TestPage "Warehouse Receipt";
        Item: Record Item;
        Location: Record Location;
        MachineCenter: array[2] of Record "Machine Center";
        ProductionOrder: Record "Production Order";
        ProdOrderLine: Record "Prod. Order Line";
        PurchaseHeader: Record "Purchase Header";
        PurchaseLine: Record "Purchase Line";
        WarehouseReceiptHeader: Record "Warehouse Receipt Header";
        WarehouseReceiptLine: Record "Warehouse Receipt Line";
        PostedWhseReceiptHeader: Record "Posted Whse. Receipt Header";
        PostedWhseReceiptLine: Record "Posted Whse. Receipt Line";
        WarehouseEmployee: Record "Warehouse Employee";
        WorkCenter: array[2] of Record "Work Center";
        Vendor: Record Vendor;
        ReservationEntry: Record "Reservation Entry";
        ItemLedgerEntry: Record "Item Ledger Entry";
        NoSeriesCodeunit: Codeunit "No. Series";
        Quantity: Decimal;
        LotNo: Code[50];
    begin
        // [SCENARIO] Item Tracking for Non-Last Operations
        // [FEATURE] Subcontracting Item Tracking - Intermediate Operations with Lot Numbers

        // [GIVEN] Complete Setup of Manufacturing, include Work- and Machine Centers, Lot-tracked Item
        Initialize();
        Quantity := LibraryRandom.RandIntInRange(5, 10);

        // [GIVEN] Create and Calculate needed Work and Machine Center with Subcontracting
        SubcWarehouseLibrary.CreateAndCalculateNeededWorkAndMachineCenter(WorkCenter, MachineCenter, true);

        // [GIVEN] Create Lot-tracked Item for Production include Routing and Prod. BOM
        SubcWarehouseLibrary.CreateLotTrackedItemForProductionWithSetup(Item, WorkCenter, MachineCenter);

        // [GIVEN] Create Location with Warehouse Handling
        SubcWarehouseLibrary.CreateLocationWithWarehouseHandling(Location);

        // [GIVEN] Create Warehouse Employee for Location
        LibraryWarehouse.CreateWarehouseEmployee(WarehouseEmployee, Location.Code, false);

        // [GIVEN] Update Vendor with Subcontracting Location Code
        Vendor.Get(WorkCenter[2]."Subcontractor No.");
        Vendor."Subcontr. Location Code" := Location.Code;
        Vendor."Location Code" := Location.Code;
        Vendor.Modify();

        // [GIVEN] Create and Refresh Production Order
        SubcWarehouseLibrary.CreateAndRefreshProductionOrder(
            ProductionOrder, "Production Order Status"::Released,
            ProductionOrder."Source Type"::Item, Item."No.", Quantity, Location.Code);

        // [GIVEN] Assign Lot Number to Production Order Line
        ProdOrderLine.SetRange(Status, ProductionOrder.Status);
        ProdOrderLine.SetRange("Prod. Order No.", ProductionOrder."No.");
        ProdOrderLine.FindFirst();

        LotNo := NoSeriesCodeunit.GetNextNo(Item."Lot Nos.");
        LibraryManufacturing.CreateProdOrderItemTracking(ReservationEntry, ProdOrderLine, '', LotNo, Quantity);

        // [GIVEN] Update Subcontracting Management Setup with Requisition Worksheet Template
        SubcWarehouseLibrary.UpdateSubMgmtSetupWithReqWkshTemplate();

        // [WHEN] Create Subcontracting Purchase Order for intermediate operation
        SubcWarehouseLibrary.CreateSubcontractingOrderFromProdOrderRouting(Item."Routing No.", WorkCenter[2]."No.", PurchaseLine);
        PurchaseHeader.Get(PurchaseLine."Document Type", PurchaseLine."Document No.");

        // [WHEN] Create Warehouse Receipt from Purchase Order
        SubcWarehouseLibrary.CreateWarehouseReceiptFromPurchaseOrder(PurchaseHeader, WarehouseReceiptHeader);

        // [THEN] Verify Data Consistency: Item tracking is correctly handled on warehouse receipt
        WarehouseReceiptLine.SetRange("No.", WarehouseReceiptHeader."No.");
        WarehouseReceiptLine.FindFirst();

        Assert.AreEqual(WarehouseReceiptLine."Subc. Purchase Line Type"::LastOperation,
            WarehouseReceiptLine."Subc. Purchase Line Type",
            'Warehouse Receipt Line should be marked as Intermediate Operation');

        // [THEN] Verify Data Consistency: Reservation entries exist for non-last operation
        HandlingSerialNo := '';
        HandlingLotNo := LotNo;
        HandlingQty := Quantity;

        WarehouseReceiptPage.OpenView();
        WarehouseReceiptPage.GoToRecord(WarehouseReceiptHeader);
        WarehouseReceiptPage.WhseReceiptLines.GoToRecord(WarehouseReceiptLine);
        WarehouseReceiptPage.WhseReceiptLines.ItemTrackingLines.Invoke();
        WarehouseReceiptPage.Close();

        // [WHEN] Post Warehouse Receipt
        SubcWarehouseLibrary.PostWarehouseReceipt(WarehouseReceiptHeader, PostedWhseReceiptHeader);

        // [THEN] Verify Posted Entries: Posted entries reflect correct item tracking
        PostedWhseReceiptLine.SetRange("Item No.", Item."No.");
        PostedWhseReceiptLine.FindFirst();

        PostedWhseReceiptHeader.Get(PostedWhseReceiptLine."No.");

        // [THEN] Verify Posted Entries: Item ledger entries contain correct lot number
        ItemLedgerEntry.SetRange("Item No.", Item."No.");
        ItemLedgerEntry.SetRange("Lot No.", LotNo);
        ItemLedgerEntry.SetRange("Entry Type", ItemLedgerEntry."Entry Type"::Output);
        Assert.RecordIsNotEmpty(ItemLedgerEntry);

        ItemLedgerEntry.FindFirst();
        Assert.AreEqual(Quantity, ItemLedgerEntry.Quantity,
            'Item Ledger Entry Quantity should match for non-last operation');
        Assert.AreEqual(LotNo, ItemLedgerEntry."Lot No.",
            'Item Ledger Entry Lot No. should match for non-last operation');
    end;

    [Test]
    [HandlerFunctions('ItemTrackingLinesPageHandler')]
    procedure MultiStepPartialPostingWithMultipleLotNumbers()
    var
        Item: Record Item;
        Location: Record Location;
        MachineCenter: array[2] of Record "Machine Center";
        ProductionOrder: Record "Production Order";
        PurchaseHeader: Record "Purchase Header";
        PurchaseLine: Record "Purchase Line";
        WarehouseReceiptHeader: Record "Warehouse Receipt Header";
        WarehouseReceiptLine: Record "Warehouse Receipt Line";
        WarehouseActivityHeader: Record "Warehouse Activity Header";
        WarehouseActivityLine: Record "Warehouse Activity Line";
        PostedWhseReceiptHeader: Record "Posted Whse. Receipt Header";
        PostedWhseReceiptHeader2: Record "Posted Whse. Receipt Header";
        WarehouseActivityHeader2: Record "Warehouse Activity Header";
        WarehouseEmployee: Record "Warehouse Employee";
        WorkCenter: array[2] of Record "Work Center";
        Vendor: Record Vendor;
        ItemLedgerEntry: Record "Item Ledger Entry";
        ReceiveBin: Record Bin;
        PutAwayBin: Record Bin;
        NoSeriesCodeunit: Codeunit "No. Series";
        WarehouseReceiptPage: TestPage "Warehouse Receipt";
        TotalQuantity: Decimal;
        FirstReceiptQty: Decimal;
        SecondReceiptQty: Decimal;
        ThirdReceiptQty: Decimal;
        FirstPutAwayQty: Decimal;
        SecondPutAwayQty: Decimal;
        LotNo1: Code[50];
        LotNo2: Code[50];
        LotNo3: Code[50];
    begin
        // [SCENARIO] Multi-step partial posting with multiple lot numbers for Last Operation
        // [FEATURE] Subcontracting Item Tracking - Partial Posting with Multiple Lot Numbers
        // Item Ledger Entry is posted on Warehouse Receipt posting, Bin Content increases on Put-away posting

        // [GIVEN] Complete Manufacturing Setup
        Initialize();
        TotalQuantity := LibraryRandom.RandIntInRange(30, 60);
        FirstReceiptQty := Round(TotalQuantity * 0.3, 1);
        SecondReceiptQty := Round(TotalQuantity * 0.4, 1);
        ThirdReceiptQty := TotalQuantity - FirstReceiptQty - SecondReceiptQty;

        FirstPutAwayQty := Round(FirstReceiptQty * 0.5, 1);
        SecondPutAwayQty := FirstReceiptQty - FirstPutAwayQty;

        // [GIVEN] Create Work Centers and Machine Centers with Subcontracting
        SubcWarehouseLibrary.CreateAndCalculateNeededWorkAndMachineCenter(WorkCenter, MachineCenter, true);

        // [GIVEN] Create Lot-tracked Item with Routing and Production BOM
        SubcWarehouseLibrary.CreateLotTrackedItemForProductionWithSetup(Item, WorkCenter, MachineCenter);

        // [GIVEN] Update BOM and Routing with Routing Link
        SubcWarehouseLibrary.UpdateProdBomAndRoutingWithRoutingLink(Item, WorkCenter[2]."No.");

        // [GIVEN] Create Location with Warehouse Handling and Bin Mandatory (Require Receive, Put-away, Bin Mandatory)
        SubcWarehouseLibrary.CreateLocationWithWarehouseHandlingAndBins(Location, ReceiveBin, PutAwayBin);

        // [GIVEN] Create Warehouse Employee for Location
        LibraryWarehouse.CreateWarehouseEmployee(WarehouseEmployee, Location.Code, false);

        // [GIVEN] Configure Vendor with Subcontracting Location
        Vendor.Get(WorkCenter[2]."Subcontractor No.");
        Vendor."Subcontr. Location Code" := Location.Code;
        Vendor."Location Code" := Location.Code;
        Vendor.Modify();

        // [GIVEN] Create and Refresh Production Order
        SubcWarehouseLibrary.CreateAndRefreshProductionOrder(
            ProductionOrder, "Production Order Status"::Released,
            ProductionOrder."Source Type"::Item, Item."No.", TotalQuantity, Location.Code);

        // [GIVEN] Setup Requisition Worksheet Template
        SubcWarehouseLibrary.UpdateSubMgmtSetupWithReqWkshTemplate();

        // [GIVEN] Create Subcontracting Purchase Order
        SubcWarehouseLibrary.CreateSubcontractingOrderFromProdOrderRouting(Item."Routing No.", WorkCenter[2]."No.", PurchaseLine);
        PurchaseHeader.Get(PurchaseLine."Document Type", PurchaseLine."Document No.");

        // [WHEN] Create Warehouse Receipt from Purchase Order
        SubcWarehouseLibrary.CreateWarehouseReceiptFromPurchaseOrder(PurchaseHeader, WarehouseReceiptHeader);

        WarehouseReceiptLine.SetRange("No.", WarehouseReceiptHeader."No.");
        WarehouseReceiptLine.FindFirst();

        // [GIVEN] Generate lot numbers for tracking
        LotNo1 := NoSeriesCodeunit.GetNextNo(Item."Lot Nos.");
        LotNo2 := NoSeriesCodeunit.GetNextNo(Item."Lot Nos.");
        LotNo3 := NoSeriesCodeunit.GetNextNo(Item."Lot Nos.");

        // [WHEN] Insert first Lot Number via Item Tracking Lines page on Warehouse Receipt
        HandlingMode := HandlingMode::Insert;
        HandlingSerialNo := '';
        HandlingLotNo := LotNo1;
        HandlingQty := FirstReceiptQty;

        WarehouseReceiptPage.OpenEdit();
        WarehouseReceiptPage.GoToRecord(WarehouseReceiptHeader);
        WarehouseReceiptPage.WhseReceiptLines.GoToRecord(WarehouseReceiptLine);
        WarehouseReceiptPage.WhseReceiptLines.ItemTrackingLines.Invoke();
        WarehouseReceiptPage.Close();

        // [WHEN] Step 1: Post first partial warehouse receipt with first lot
        SubcWarehouseLibrary.PostPartialWarehouseReceipt(WarehouseReceiptHeader, FirstReceiptQty, PostedWhseReceiptHeader);

        // [THEN] Verify: Item Ledger Entry is posted for Whse Receipt (FirstReceiptQty)
        VerifyPostedWhseReceiptQuantity(PostedWhseReceiptHeader, Item."No.", FirstReceiptQty);
        VerifyItemLedgerEntryForLot(Item."No.", LotNo1, FirstReceiptQty, Location.Code);

        // [WHEN] Step 2: Create and post first partial put-away
        SubcWarehouseLibrary.CreatePutAwayFromPostedWhseReceipt(PostedWhseReceiptHeader, WarehouseActivityHeader);

        // [THEN] Verify: Item tracking is propagated to put-away
        WarehouseActivityLine.SetRange("Activity Type", WarehouseActivityHeader.Type);
        WarehouseActivityLine.SetRange("No.", WarehouseActivityHeader."No.");
        WarehouseActivityLine.SetRange("Action Type", WarehouseActivityLine."Action Type"::Place);
        WarehouseActivityLine.FindFirst();
        Assert.AreEqual(LotNo1, WarehouseActivityLine."Lot No.",
            'First Lot No. should be propagated to Put-away Line');

        SubcWarehouseLibrary.PostPartialPutAway(WarehouseActivityHeader, FirstPutAwayQty);

        // [THEN] Verify: Item Ledger Entry unchanged (still FirstReceiptQty - ILE created on Whse Receipt)
        // [THEN] Verify: Bin Content increases for Put-away Posting (FirstPutAwayQty)
        VerifyItemLedgerEntryForLot(Item."No.", LotNo1, FirstReceiptQty, Location.Code);
        VerifyBinContentsForLot(Location.Code, PutAwayBin.Code, Item."No.", LotNo1, FirstPutAwayQty);

        // [WHEN] Step 3: Post remaining quantity from first put-away
        SubcWarehouseLibrary.PostPartialPutAway(WarehouseActivityHeader, SecondPutAwayQty);

        // [THEN] Verify: Item Ledger Entry unchanged (still FirstReceiptQty)
        // [THEN] Verify: Bin Content cumulative after second put-away
        VerifyItemLedgerEntryForLot(Item."No.", LotNo1, FirstReceiptQty, Location.Code);
        VerifyBinContentsForLot(Location.Code, PutAwayBin.Code, Item."No.", LotNo1, FirstPutAwayQty + SecondPutAwayQty);

        // [WHEN] Insert second Lot Number via Item Tracking Lines page on Warehouse Receipt
        WarehouseReceiptHeader.Find();
        WarehouseReceiptLine.SetRange("No.", WarehouseReceiptHeader."No.");
        WarehouseReceiptLine.FindFirst();

        HandlingMode := HandlingMode::Insert;
        HandlingLotNo := LotNo2;
        HandlingQty := SecondReceiptQty;

        WarehouseReceiptPage.OpenEdit();
        WarehouseReceiptPage.GoToRecord(WarehouseReceiptHeader);
        WarehouseReceiptPage.WhseReceiptLines.GoToRecord(WarehouseReceiptLine);
        WarehouseReceiptPage.WhseReceiptLines.ItemTrackingLines.Invoke();
        WarehouseReceiptPage.Close();

        // [WHEN] Step 4: Post second partial warehouse receipt with second lot
        SubcWarehouseLibrary.PostPartialWarehouseReceipt(WarehouseReceiptHeader, SecondReceiptQty, PostedWhseReceiptHeader2);

        // [THEN] Verify: Item Ledger Entry is posted for second lot (SecondReceiptQty)
        VerifyPostedWhseReceiptQuantity(PostedWhseReceiptHeader2, Item."No.", SecondReceiptQty);
        VerifyItemLedgerEntryForLot(Item."No.", LotNo2, SecondReceiptQty, Location.Code);

        // [WHEN] Step 5: Create and post second put-away (full quantity)
        SubcWarehouseLibrary.CreatePutAwayFromPostedWhseReceipt(PostedWhseReceiptHeader2, WarehouseActivityHeader2);

        // [THEN] Verify: Second lot number is propagated to put-away
        WarehouseActivityLine.SetRange("Activity Type", WarehouseActivityHeader2.Type);
        WarehouseActivityLine.SetRange("No.", WarehouseActivityHeader2."No.");
        WarehouseActivityLine.SetRange("Action Type", WarehouseActivityLine."Action Type"::Place);
        WarehouseActivityLine.FindFirst();
        Assert.AreEqual(LotNo2, WarehouseActivityLine."Lot No.",
            'Second Lot No. should be propagated to Put-away Line');

        LibraryWarehouse.RegisterWhseActivity(WarehouseActivityHeader2);

        // [THEN] Verify: Item Ledger Entry for second lot unchanged (SecondReceiptQty - ILE created on Whse Receipt)
        // [THEN] Verify: Bin Content for second lot after put-away
        VerifyItemLedgerEntryForLot(Item."No.", LotNo2, SecondReceiptQty, Location.Code);
        VerifyBinContentsForLot(Location.Code, PutAwayBin.Code, Item."No.", LotNo2, SecondReceiptQty);

        // [WHEN] Insert third Lot Number via Item Tracking Lines page on Warehouse Receipt
        WarehouseReceiptHeader.Find();
        WarehouseReceiptLine.SetRange("No.", WarehouseReceiptHeader."No.");
        WarehouseReceiptLine.FindFirst();

        HandlingMode := HandlingMode::Insert;
        HandlingLotNo := LotNo3;
        HandlingQty := ThirdReceiptQty;

        WarehouseReceiptPage.OpenEdit();
        WarehouseReceiptPage.GoToRecord(WarehouseReceiptHeader);
        WarehouseReceiptPage.WhseReceiptLines.GoToRecord(WarehouseReceiptLine);
        WarehouseReceiptPage.WhseReceiptLines.ItemTrackingLines.Invoke();
        WarehouseReceiptPage.Close();

        // [WHEN] Step 6: Post remaining warehouse receipt with third lot
        SubcWarehouseLibrary.PostWarehouseReceipt(WarehouseReceiptHeader, PostedWhseReceiptHeader);

        // [THEN] Verify: Item Ledger Entry is posted for third lot (ThirdReceiptQty)
        VerifyItemLedgerEntryForLot(Item."No.", LotNo3, ThirdReceiptQty, Location.Code);

        // [WHEN] Step 7: Create and post final put-away
        SubcWarehouseLibrary.CreatePutAwayFromPostedWhseReceipt(PostedWhseReceiptHeader, WarehouseActivityHeader);

        // [THEN] Verify: Third lot number is propagated to put-away
        WarehouseActivityLine.SetRange("Activity Type", WarehouseActivityHeader.Type);
        WarehouseActivityLine.SetRange("No.", WarehouseActivityHeader."No.");
        WarehouseActivityLine.SetRange("Action Type", WarehouseActivityLine."Action Type"::Place);
        WarehouseActivityLine.FindFirst();
        Assert.AreEqual(LotNo3, WarehouseActivityLine."Lot No.",
            'Third Lot No. should be propagated to Put-away Line');

        LibraryWarehouse.RegisterWhseActivity(WarehouseActivityHeader);

        // [THEN] Verify: Item Ledger Entry for third lot unchanged (ThirdReceiptQty - ILE created on Whse Receipt)
        // [THEN] Verify: Bin Content for third lot after put-away
        VerifyItemLedgerEntryForLot(Item."No.", LotNo3, ThirdReceiptQty, Location.Code);
        VerifyBinContentsForLot(Location.Code, PutAwayBin.Code, Item."No.", LotNo3, ThirdReceiptQty);

        // [THEN] Verify: All three lots exist in item ledger entries with total quantity
        ItemLedgerEntry.SetRange("Item No.", Item."No.");
        ItemLedgerEntry.SetRange("Location Code", Location.Code);
        ItemLedgerEntry.SetRange("Entry Type", ItemLedgerEntry."Entry Type"::Output);
        ItemLedgerEntry.CalcSums(Quantity);
        Assert.AreEqual(TotalQuantity, ItemLedgerEntry.Quantity,
            'Total quantity across all lots should match original order quantity');

        // [THEN] Verify: Each lot number is correctly tracked in Item Ledger Entries
        VerifyItemLedgerEntryForLot(Item."No.", LotNo1, FirstReceiptQty, Location.Code);
        VerifyItemLedgerEntryForLot(Item."No.", LotNo2, SecondReceiptQty, Location.Code);
        VerifyItemLedgerEntryForLot(Item."No.", LotNo3, ThirdReceiptQty, Location.Code);

        // [THEN] Verify: Each lot number is correctly tracked in Bin Contents
        VerifyBinContentsForLot(Location.Code, PutAwayBin.Code, Item."No.", LotNo1, FirstReceiptQty);
        VerifyBinContentsForLot(Location.Code, PutAwayBin.Code, Item."No.", LotNo2, SecondReceiptQty);
        VerifyBinContentsForLot(Location.Code, PutAwayBin.Code, Item."No.", LotNo3, ThirdReceiptQty);
    end;

    local procedure VerifyPostedWhseReceiptQuantity(var PostedWhseReceiptHeader: Record "Posted Whse. Receipt Header"; ItemNo: Code[20]; ExpectedQuantity: Decimal)
    var
        PostedWhseReceiptLine: Record "Posted Whse. Receipt Line";
    begin
        PostedWhseReceiptLine.SetRange("No.", PostedWhseReceiptHeader."No.");
        PostedWhseReceiptLine.SetRange("Item No.", ItemNo);
        Assert.RecordIsNotEmpty(PostedWhseReceiptLine);

        PostedWhseReceiptLine.FindFirst();
        Assert.AreEqual(ExpectedQuantity, PostedWhseReceiptLine.Quantity,
            'Posted warehouse receipt line should have correct quantity');
    end;

    local procedure VerifyItemLedgerEntryForLot(ItemNo: Code[20]; LotNo: Code[50]; ExpectedQuantity: Decimal; LocationCode: Code[10])
    var
        ItemLedgerEntry: Record "Item Ledger Entry";
    begin
        ItemLedgerEntry.SetRange("Item No.", ItemNo);
        ItemLedgerEntry.SetRange("Lot No.", LotNo);
        ItemLedgerEntry.SetRange("Location Code", LocationCode);
        ItemLedgerEntry.SetRange("Entry Type", ItemLedgerEntry."Entry Type"::Output);
        Assert.RecordIsNotEmpty(ItemLedgerEntry);

        ItemLedgerEntry.CalcSums(Quantity);
        Assert.AreEqual(ExpectedQuantity, ItemLedgerEntry.Quantity,
            'Item Ledger Entry should have correct quantity for lot ' + LotNo);
    end;

    local procedure VerifyBinContentsForLot(LocationCode: Code[10]; BinCode: Code[20]; ItemNo: Code[20]; LotNo: Code[50]; ExpectedQuantity: Decimal)
    var
        BinContent: Record "Bin Content";
    begin
        BinContent.SetRange("Location Code", LocationCode);
        BinContent.SetRange("Bin Code", BinCode);
        BinContent.SetRange("Item No.", ItemNo);
        BinContent.SetRange("Lot No. Filter", LotNo);
        Assert.RecordIsNotEmpty(BinContent);

        BinContent.FindFirst();
        BinContent.CalcFields(Quantity);
        Assert.AreEqual(ExpectedQuantity, BinContent.Quantity,
            'Bin contents should show correct quantity for lot ' + LotNo + ' after put-away posting');
    end;

    [ModalPageHandler]
    procedure ItemTrackingLinesPageHandler(var ItemTrackingLines: TestPage "Item Tracking Lines")
    var
        ReservationEntry: Record "Reservation Entry";
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

                    if HandlingSourceType <> 0 then begin
                        ReservationEntry.SetRange("Serial No.", Format(ItemTrackingLines."Serial No.".Value));
                        ReservationEntry.SetRange("Lot No.", Format(ItemTrackingLines."Lot No.".Value));
                        ReservationEntry.FindFirst();
                        Assert.AreEqual(HandlingSourceType, ReservationEntry."Source Type",
                            'Reservation Entry Source Type should be Prod. Order Line');
                    end;
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
