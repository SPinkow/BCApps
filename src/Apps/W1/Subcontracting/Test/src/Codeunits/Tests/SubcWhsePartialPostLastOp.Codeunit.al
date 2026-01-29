// ------------------------------------------------------------------------------------------------
// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License. See License.txt in the project root for license information.
// ------------------------------------------------------------------------------------------------
namespace Microsoft.Manufacturing.Subcontracting.Test;

using Microsoft.Finance.GeneralLedger.Ledger;
using Microsoft.Finance.GeneralLedger.Setup;
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

codeunit 140002 "Subc. Whse Partial Last Op"
{
    // [FEATURE] Subcontracting Warehouse Partial Posting - Last Operation Tests
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
        LibraryTestInitialize.OnTestInitialize(Codeunit::"Subc. Whse Partial Last Op");
        LibrarySetupStorage.Restore();

        SubcontractingMgmtLibrary.Initialize();
        SubcLibraryMfgManagement.Initialize();
        SubSetupLibrary.InitSetupFields();

        if IsInitialized then
            exit;

        LibraryTestInitialize.OnBeforeTestSuiteInitialize(Codeunit::"Subc. Whse Partial Last Op");

        LibraryERMCountryData.CreateVATData();
        LibraryERMCountryData.UpdateGeneralPostingSetup();
        LibrarySetupStorage.Save(Database::"General Ledger Setup");

        IsInitialized := true;
        Commit();
        LibraryTestInitialize.OnAfterTestSuiteInitialize(Codeunit::"Subc. Whse Partial Last Op");
    end;

    [Test]
    procedure PartialWhseReceiptPostingForLastOperation()
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
        ReceiveBin: Record Bin;
        PutAwayBin: Record Bin;
        Quantity: Decimal;
        PartialQuantity: Decimal;
    begin
        // [SCENARIO] Post partial quantity of warehouse receipt for Last Operation
        // [FEATURE] Subcontracting Warehouse Partial Posting - Last Operation

        // [GIVEN] Complete Manufacturing Setup with Work Centers, Machine Centers, and Item
        Initialize();
        Quantity := LibraryRandom.RandIntInRange(10, 20);
        PartialQuantity := Round(Quantity / 2, 1);

        // [GIVEN] Create Work Centers and Machine Centers with Subcontracting
        SubcWarehouseLibrary.CreateAndCalculateNeededWorkAndMachineCenter(WorkCenter, MachineCenter, true);

        // [GIVEN] Create Item with Routing and Production BOM
        SubcWarehouseLibrary.CreateItemForProductionIncludeRoutingAndProdBOM(Item, WorkCenter, MachineCenter);

        // [GIVEN] Update BOM and Routing with Routing Link
        SubcWarehouseLibrary.UpdateProdBomAndRoutingWithRoutingLink(Item, WorkCenter[2]."No.");

        // [GIVEN] Create Location with Warehouse Handling and Bin Mandatory (Require Receive, Put-away, Bin Mandatory)
        // Creates both Receive Bin (for warehouse receipt) and Put-away Bin (for put-away destination)
        SubcWarehouseLibrary.CreateLocationWithWarehouseHandlingAndBins(Location, ReceiveBin, PutAwayBin);

        // [GIVEN] Configure Vendor with Subcontracting Location
        Vendor.Get(WorkCenter[2]."Subcontractor No.");
        Vendor."Subcontr. Location Code" := Location.Code;
        Vendor."Location Code" := Location.Code;
        Vendor.Modify();

        // [GIVEN] Create and Refresh Production Order
        SubcWarehouseLibrary.CreateAndRefreshProductionOrder(
            ProductionOrder, "Production Order Status"::Released,
            ProductionOrder."Source Type"::Item, Item."No.", Quantity, Location.Code);

        // [GIVEN] Setup Requisition Worksheet Template
        SubcWarehouseLibrary.UpdateSubMgmtSetupWithReqWkshTemplate();

        // [GIVEN] Create Subcontracting Purchase Order
        SubcWarehouseLibrary.CreateSubcontractingOrderFromProdOrderRouting(Item."Routing No.", WorkCenter[2]."No.", PurchaseLine);
        PurchaseHeader.Get(PurchaseLine."Document Type", PurchaseLine."Document No.");

        // [GIVEN] Create Warehouse Receipt from Purchase Order
        SubcWarehouseLibrary.CreateWarehouseReceiptFromPurchaseOrder(PurchaseHeader, WarehouseReceiptHeader);

        // [WHEN] Post Partial Warehouse Receipt
        SubcWarehouseLibrary.PostPartialWarehouseReceipt(WarehouseReceiptHeader, PartialQuantity, PostedWhseReceiptHeader);

        // [THEN] Verify Posted Entries: Posted warehouse receipt created for partial quantity
        Assert.AreNotEqual('', PostedWhseReceiptHeader."No.",
            'Posted warehouse receipt should be created');

        // [THEN] Verify Quantity Reconciliation: Posted warehouse receipt has correct partial quantity
        VerifyPostedWhseReceiptQuantity(PostedWhseReceiptHeader, Item."No.", PartialQuantity);

        // [THEN] Verify Quantity Reconciliation: Remaining quantity is correct on warehouse receipt
        WarehouseReceiptLine.SetRange("No.", WarehouseReceiptHeader."No.");
        WarehouseReceiptLine.FindFirst();
        WarehouseReceiptLine.SetRange("No.", WarehouseReceiptHeader."No.");
        WarehouseReceiptLine.FindFirst();
        Assert.AreEqual(Quantity - PartialQuantity, WarehouseReceiptLine."Qty. Outstanding",
            'Warehouse receipt line should have correct outstanding quantity after partial posting');
    end;

    [Test]
    procedure PartialPutAwayPostingForLastOperation()
    var
        Item: Record Item;
        Location: Record Location;
        MachineCenter: array[2] of Record "Machine Center";
        ProductionOrder: Record "Production Order";
        PurchaseHeader: Record "Purchase Header";
        PurchaseLine: Record "Purchase Line";
        WarehouseReceiptHeader: Record "Warehouse Receipt Header";
        WarehouseActivityHeader: Record "Warehouse Activity Header";
        WarehouseActivityLine: Record "Warehouse Activity Line";
        PostedWhseReceiptHeader: Record "Posted Whse. Receipt Header";
        WorkCenter: array[2] of Record "Work Center";
        Vendor: Record Vendor;
        ReceiveBin: Record Bin;
        PutAwayBin: Record Bin;
        Quantity: Decimal;
        PartialReceiptQty: Decimal;
        PartialPutAwayQty: Decimal;
    begin
        // [SCENARIO] Post partial quantity of put-away created from partially received warehouse receipt for Last Operation
        // [FEATURE] Subcontracting Warehouse Partial Posting - Last Operation

        // [GIVEN] Complete Manufacturing Setup
        Initialize();
        Quantity := LibraryRandom.RandIntInRange(20, 40);
        PartialReceiptQty := Round(Quantity / 2, 1);
        PartialPutAwayQty := Round(PartialReceiptQty / 2, 1);

        // [GIVEN] Create Work Centers and Machine Centers with Subcontracting
        SubcWarehouseLibrary.CreateAndCalculateNeededWorkAndMachineCenter(WorkCenter, MachineCenter, true);

        // [GIVEN] Create Item with Routing and Production BOM
        SubcWarehouseLibrary.CreateItemForProductionIncludeRoutingAndProdBOM(Item, WorkCenter, MachineCenter);

        // [GIVEN] Update BOM and Routing with Routing Link
        SubcWarehouseLibrary.UpdateProdBomAndRoutingWithRoutingLink(Item, WorkCenter[2]."No.");

        // [GIVEN] Create Location with Warehouse Handling and Bin Mandatory (Require Receive, Put-away, Bin Mandatory)
        // Creates both Receive Bin (for warehouse receipt) and Put-away Bin (for put-away destination)
        SubcWarehouseLibrary.CreateLocationWithWarehouseHandlingAndBins(Location, ReceiveBin, PutAwayBin);

        // [GIVEN] Configure Vendor with Subcontracting Location
        Vendor.Get(WorkCenter[2]."Subcontractor No.");
        Vendor."Subcontr. Location Code" := Location.Code;
        Vendor."Location Code" := Location.Code;
        Vendor.Modify();

        // [GIVEN] Create and Refresh Production Order
        SubcWarehouseLibrary.CreateAndRefreshProductionOrder(
            ProductionOrder, "Production Order Status"::Released,
            ProductionOrder."Source Type"::Item, Item."No.", Quantity, Location.Code);

        // [GIVEN] Setup Requisition Worksheet Template
        SubcWarehouseLibrary.UpdateSubMgmtSetupWithReqWkshTemplate();

        // [GIVEN] Create Subcontracting Purchase Order
        SubcWarehouseLibrary.CreateSubcontractingOrderFromProdOrderRouting(Item."Routing No.", WorkCenter[2]."No.", PurchaseLine);
        PurchaseHeader.Get(PurchaseLine."Document Type", PurchaseLine."Document No.");

        // [GIVEN] Create and Post Partial Warehouse Receipt
        SubcWarehouseLibrary.CreateWarehouseReceiptFromPurchaseOrder(PurchaseHeader, WarehouseReceiptHeader);
        SubcWarehouseLibrary.PostPartialWarehouseReceipt(WarehouseReceiptHeader, PartialReceiptQty, PostedWhseReceiptHeader);

        // [GIVEN] Create Put-away from Posted Warehouse Receipt
        SubcWarehouseLibrary.CreatePutAwayFromPostedWhseReceipt(PostedWhseReceiptHeader, WarehouseActivityHeader);

        // [WHEN] Post Partial Put-away
        SubcWarehouseLibrary.PostPartialPutAway(WarehouseActivityHeader, PartialPutAwayQty);

        // [THEN] Verify Posted Entries: Item ledger entry is created for partial quantity
        VerifyItemLedgerEntry(Item."No.", PartialReceiptQty, Location.Code);

        // [THEN] Verify Posted Entries: Capacity ledger entry is created for partial quantity
        VerifyCapacityLedgerEntry(WorkCenter[2]."No.", PartialReceiptQty);

        // [THEN] Verify Bin Management: Inventory updated for partial quantity
        VerifyBinContents(Location.Code, PutAwayBin.Code, Item."No.", PartialPutAwayQty);

        // [THEN] Verify Quantity Reconciliation: Put-away has correct outstanding quantity
        WarehouseActivityLine.SetRange("Activity Type", WarehouseActivityLine."Activity Type"::"Put-away");
        WarehouseActivityLine.SetRange("No.", WarehouseActivityHeader."No.");
        WarehouseActivityLine.SetRange("Action Type", WarehouseActivityLine."Action Type"::Take);
        if WarehouseActivityLine.FindFirst() then
            Assert.AreEqual(PartialReceiptQty - PartialPutAwayQty,
                WarehouseActivityLine."Qty. Outstanding",
                'Put-away line should have correct outstanding quantity after partial posting');
    end;

    [Test]
    procedure MultiStepPartialPostingForLastOperation()
    var
        Item: Record Item;
        Location: Record Location;
        MachineCenter: array[2] of Record "Machine Center";
        ProductionOrder: Record "Production Order";
        PurchaseHeader: Record "Purchase Header";
        PurchaseLine: Record "Purchase Line";
        WarehouseReceiptHeader: Record "Warehouse Receipt Header";
        WarehouseActivityHeader: Record "Warehouse Activity Header";
        PostedWhseReceiptHeader: Record "Posted Whse. Receipt Header";
        PostedWhseReceiptHeader2: Record "Posted Whse. Receipt Header";
        WarehouseActivityHeader2: Record "Warehouse Activity Header";
        WorkCenter: array[2] of Record "Work Center";
        Vendor: Record Vendor;
        ReceiveBin: Record Bin;
        PutAwayBin: Record Bin;
        TotalQuantity: Decimal;
        FirstReceiptQty: Decimal;
        SecondReceiptQty: Decimal;
        ThirdReceiptQty: Decimal;
        FirstPutAwayQty: Decimal;
        SecondPutAwayQty: Decimal;
        ThirdPutAwayQty: Decimal;
    begin
        // [SCENARIO] Post single order in multiple partial steps until full quantity processed for Last Operation
        // [FEATURE] Subcontracting Warehouse Multi-step Partial Posting - Last Operation

        // [GIVEN] Complete Manufacturing Setup
        Initialize();
        TotalQuantity := LibraryRandom.RandIntInRange(30, 60);
        FirstReceiptQty := Round(TotalQuantity * 0.3, 1);
        SecondReceiptQty := Round(TotalQuantity * 0.4, 1);
        ThirdReceiptQty := TotalQuantity - FirstReceiptQty - SecondReceiptQty;

        FirstPutAwayQty := Round(FirstReceiptQty * 0.5, 1);
        SecondPutAwayQty := FirstReceiptQty - FirstPutAwayQty;
        ThirdPutAwayQty := SecondReceiptQty;

        // [GIVEN] Create Work Centers and Machine Centers with Subcontracting
        SubcWarehouseLibrary.CreateAndCalculateNeededWorkAndMachineCenter(WorkCenter, MachineCenter, true);

        // [GIVEN] Create Item with Routing and Production BOM
        SubcWarehouseLibrary.CreateItemForProductionIncludeRoutingAndProdBOM(Item, WorkCenter, MachineCenter);

        // [GIVEN] Update BOM and Routing with Routing Link
        SubcWarehouseLibrary.UpdateProdBomAndRoutingWithRoutingLink(Item, WorkCenter[2]."No.");

        // [GIVEN] Create Location with Warehouse Handling and Bin Mandatory (Require Receive, Put-away, Bin Mandatory)
        // Creates both Receive Bin (for warehouse receipt) and Put-away Bin (for put-away destination)
        SubcWarehouseLibrary.CreateLocationWithWarehouseHandlingAndBins(Location, ReceiveBin, PutAwayBin);

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

        // [GIVEN] Create Warehouse Receipt from Purchase Order
        SubcWarehouseLibrary.CreateWarehouseReceiptFromPurchaseOrder(PurchaseHeader, WarehouseReceiptHeader);

        // [WHEN] Step 1: Post first partial warehouse receipt
        SubcWarehouseLibrary.PostPartialWarehouseReceipt(WarehouseReceiptHeader, FirstReceiptQty, PostedWhseReceiptHeader);

        // [THEN] Verify Quantity Reconciliation: First receipt quantity is correct
        VerifyPostedWhseReceiptQuantity(PostedWhseReceiptHeader, Item."No.", FirstReceiptQty);

        // [WHEN] Step 2: Create and post first partial put-away
        SubcWarehouseLibrary.CreatePutAwayFromPostedWhseReceipt(PostedWhseReceiptHeader, WarehouseActivityHeader);
        SubcWarehouseLibrary.PostPartialPutAway(WarehouseActivityHeader, FirstPutAwayQty);

        // [THEN] Verify Quantity Reconciliation: First put-away quantity is correct
        VerifyItemLedgerEntry(Item."No.", FirstReceiptQty, Location.Code);
        VerifyBinContents(Location.Code, PutAwayBin.Code, Item."No.", FirstPutAwayQty);

        // [WHEN] Step 3: Post remaining quantity from first put-away
        SubcWarehouseLibrary.PostPartialPutAway(WarehouseActivityHeader, SecondPutAwayQty);

        // [THEN] Verify Quantity Reconciliation: Cumulative quantity is correct
        VerifyItemLedgerEntry(Item."No.", FirstReceiptQty, Location.Code);
        VerifyBinContents(Location.Code, PutAwayBin.Code, Item."No.", FirstPutAwayQty + SecondPutAwayQty);

        // [WHEN] Step 4: Post second partial warehouse receipt
        SubcWarehouseLibrary.PostPartialWarehouseReceipt(WarehouseReceiptHeader, SecondReceiptQty, PostedWhseReceiptHeader2);

        // [THEN] Verify Quantity Reconciliation: Second receipt quantity is correct
        VerifyPostedWhseReceiptQuantity(PostedWhseReceiptHeader2, Item."No.", SecondReceiptQty);

        // [WHEN] Step 5: Create and post second put-away (full quantity)
        SubcWarehouseLibrary.CreatePutAwayFromPostedWhseReceipt(PostedWhseReceiptHeader2, WarehouseActivityHeader2);
        SubcWarehouseLibrary.PostPutAway(WarehouseActivityHeader2);

        // [THEN] Verify Quantity Reconciliation: Total posted quantity through all steps
        VerifyItemLedgerEntry(Item."No.",
            FirstReceiptQty + SecondReceiptQty, Location.Code);
        VerifyCapacityLedgerEntry(WorkCenter[2]."No.",
            FirstReceiptQty + SecondReceiptQty);
        VerifyBinContents(Location.Code, PutAwayBin.Code, Item."No.",
            FirstReceiptQty + SecondReceiptQty);
        // [WHEN] Step 6: Post remaining warehouse receipt
        SubcWarehouseLibrary.PostWarehouseReceipt(WarehouseReceiptHeader, PostedWhseReceiptHeader);

        // [WHEN] Step 7: Create and post final put-away
        SubcWarehouseLibrary.CreatePutAwayFromPostedWhseReceipt(PostedWhseReceiptHeader, WarehouseActivityHeader);
        SubcWarehouseLibrary.PostPutAway(WarehouseActivityHeader);

        // [THEN] Verify Data Consistency: Final quantities match original order quantity
        VerifyItemLedgerEntry(Item."No.", TotalQuantity, Location.Code);
        VerifyCapacityLedgerEntry(WorkCenter[2]."No.", TotalQuantity);
        VerifyBinContents(Location.Code, PutAwayBin.Code, Item."No.", TotalQuantity);

        // [THEN] Verify UoM: Base quantity calculations are correct across all documents
        VerifyUoMBaseQuantityCalculations(Item."No.", TotalQuantity, Location.Code);
    end;

    local procedure VerifyItemLedgerEntry(ItemNo: Code[20]; ExpectedQuantity: Decimal; LocationCode: Code[10])
    var
        ItemLedgerEntry: Record "Item Ledger Entry";
    begin
        ItemLedgerEntry.SetRange("Item No.", ItemNo);
        ItemLedgerEntry.SetRange("Location Code", LocationCode);
        ItemLedgerEntry.SetRange("Entry Type", ItemLedgerEntry."Entry Type"::Output);
        Assert.RecordIsNotEmpty(ItemLedgerEntry);

        ItemLedgerEntry.CalcSums(Quantity);
        Assert.AreEqual(ExpectedQuantity, ItemLedgerEntry.Quantity,
            'Item Ledger Entry should have correct output quantity');
    end;

    local procedure VerifyCapacityLedgerEntry(WorkCenterNo: Code[20]; ExpectedQuantity: Decimal)
    var
        CapacityLedgerEntry: Record "Capacity Ledger Entry";
    begin
        CapacityLedgerEntry.SetRange(Type, CapacityLedgerEntry.Type::"Work Center");
        CapacityLedgerEntry.SetRange("No.", WorkCenterNo);
        Assert.RecordIsNotEmpty(CapacityLedgerEntry);

        CapacityLedgerEntry.CalcSums("Output Quantity");
        Assert.AreEqual(ExpectedQuantity, CapacityLedgerEntry."Output Quantity",
            'Capacity Ledger Entry should have correct output quantity');
    end;

    local procedure VerifyBinContents(LocationCode: Code[10]; BinCode: Code[20]; ItemNo: Code[20]; ExpectedQuantity: Decimal)
    var
        BinContent: Record "Bin Content";
    begin
        BinContent.SetRange("Location Code", LocationCode);
        BinContent.SetRange("Bin Code", BinCode);
        BinContent.SetRange("Item No.", ItemNo);
        Assert.RecordIsNotEmpty(BinContent);

        BinContent.FindFirst();
        BinContent.CalcFields(Quantity);
        Assert.AreEqual(ExpectedQuantity, BinContent.Quantity,
            'Bin contents should show correct quantity after put-away posting');
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

    local procedure VerifyUoMBaseQuantityCalculations(ItemNo: Code[20]; ExpectedQuantity: Decimal; LocationCode: Code[10])
    var
        ItemLedgerEntry: Record "Item Ledger Entry";
    begin
        ItemLedgerEntry.SetRange("Item No.", ItemNo);
        ItemLedgerEntry.SetRange("Location Code", LocationCode);
        ItemLedgerEntry.SetRange("Entry Type", ItemLedgerEntry."Entry Type"::Output);
        Assert.RecordIsNotEmpty(ItemLedgerEntry);

        ItemLedgerEntry.CalcSums(Quantity);
        Assert.AreEqual(ExpectedQuantity, ItemLedgerEntry.Quantity,
            'UoM base quantity calculations should be correct across all documents');
    end;
}
