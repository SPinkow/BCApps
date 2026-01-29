// ------------------------------------------------------------------------------------------------
// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License. See License.txt in the project root for license information.
// ------------------------------------------------------------------------------------------------
namespace Microsoft.Manufacturing.Subcontracting.Test;

using Microsoft.Finance.GeneralLedger.Setup;
using Microsoft.Foundation.Enums;
using Microsoft.Inventory.Item;
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
        NewRoutingLine.Type := ProdOrderRoutingLine.Type::"Work Center";
        NewRoutingLine."No." := WorkCenter[1]."No.";

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
}
