// ------------------------------------------------------------------------------------------------
// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License. See License.txt in the project root for license information.
// ------------------------------------------------------------------------------------------------
// namespace Microsoft.Manufacturing.Subcontracting;

// using Microsoft.Inventory.Transfer;

codeunit 99001551 "Subc. WhsePostReceipt Ext"
{
    [EventSubscriber(ObjectType::Codeunit, Codeunit::"TransferOrder-Post Receipt", OnAfterTransRcptLineModify, '', false, false)]
    local procedure OnAfterTransRcptLineModify(var TransferReceiptLine: Record "Transfer Receipt Line"; TransferLine: Record "Transfer Line"; CommitIsSuppressed: Boolean)
    var
        SubcontrMgmt: Codeunit "Subcontracting Management";
    begin
        SubcontrMgmt.TransferReservationEntryFromPstTransferLineToProdOrderComp(TransferReceiptLine);
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Purchases Warehouse Mgt.", OnAfterGetQuantityRelatedParameter, '', false, false)]
    local procedure "Purchases Warehouse Mgt._OnAfterGetQuantityRelatedParameter"(PurchaseLine: Record Microsoft.Purchases.Document."Purchase Line"; var QtyPerUoM: Decimal; var QtyBasePurchaseLine: Decimal)
    var
        Item: Record Microsoft.Inventory.Item.Item;
        UOMMgt: Codeunit "Unit of Measure Management";
    begin
        if PurchaseLine."Subc. Purchase Line Type" = "Subc. Purchase Line Type"::LastOperation then begin
            Item.Get(PurchaseLine."No.");
            QtyPerUoM := UOMMgt.GetQtyPerUnitOfMeasure(Item, PurchaseLine."Unit of Measure Code");
            QtyBasePurchaseLine := PurchaseLine.CalcBaseQtyFromQuantity(PurchaseLine.Quantity, PurchaseLine.FieldCaption("Qty. Rounding Precision"), PurchaseLine.FieldCaption("Quantity"), PurchaseLine.FieldCaption("Quantity (Base)"));
        end;
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Purchases Warehouse Mgt.", OnPurchLine2ReceiptLineOnAfterInitNewLine, '', false, false)]
    local procedure "Purchases Warehouse Mgt._OnPurchLine2ReceiptLineOnAfterInitNewLine"(var WarehouseReceiptLine: Record "Warehouse Receipt Line"; WarehouseReceiptHeader: Record "Warehouse Receipt Header"; PurchaseLine: Record "Purchase Line"; var IsHandled: Boolean)
    begin
        WarehouseReceiptLine."Subc. Purchase Line Type" := PurchaseLine."Subc. Purchase Line Type";
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Purchases Warehouse Mgt.", OnBeforeCheckIfPurchLine2ReceiptLine, '', false, false)]
    local procedure "Purchases Warehouse Mgt._OnBeforeCheckIfPurchLine2ReceiptLine"(var PurchaseLine: Record "Purchase Line"; var ReturnValue: Boolean; var IsHandled: Boolean)
    var
        OutstandingQtyBase: Decimal;
        WhseOutstandingQtyBase: Decimal;
        QtyPerUoM: Decimal;
    begin
        case PurchaseLine."Subc. Purchase Line Type" of
            "Subc. Purchase Line Type"::None:
                exit;
            "Subc. Purchase Line Type"::LastOperation,
            "Subc. Purchase Line Type"::NotLastOperation:
                begin
                    PurchaseLine.CalcFields("Whse. Outstanding Quantity");
                    OutstandingQtyBase := PurchaseLine.CalcBaseQtyFromQuantity(PurchaseLine."Outstanding Quantity", PurchaseLine.FieldCaption("Qty. Rounding Precision"), PurchaseLine.FieldCaption("Outstanding Quantity"), PurchaseLine.FieldCaption("Outstanding Qty. (Base)"));
                    WhseOutstandingQtyBase := PurchaseLine.CalcBaseQtyFromQuantity(PurchaseLine."Whse. Outstanding Quantity", PurchaseLine.FieldCaption("Qty. Rounding Precision"), PurchaseLine.FieldCaption("Whse. Outstanding Quantity"), PurchaseLine.FieldCaption("Whse. Outstanding Qty. (Base)"));
                    ReturnValue := (Abs(OutstandingQtyBase) > Abs(WhseOutstandingQtyBase));
                    IsHandled := true;
                end;
        end;
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Whse.-Purch. Release", OnReleaseOnBeforeCreateWhseRequest, '', false, false)]
    local procedure "Whse.-Purch. Release_OnReleaseOnBeforeCreateWhseRequest"(var PurchaseLine: Record "Purchase Line"; var DoCreateWhseRequest: Boolean)
    begin
        DoCreateWhseRequest := DoCreateWhseRequest or PurchaseLine.IsInventoriableItem();
    end;

    [EventSubscriber(ObjectType::Table, Database::"Warehouse Receipt Line", OnBeforeCalcBaseQty, '', false, false)]
    local procedure "Warehouse Receipt Line_OnBeforeCalcBaseQty"(var WarehouseReceiptLine: Record "Warehouse Receipt Line"; var Qty: Decimal; FromFieldName: Text; ToFieldName: Text; var SuppressQtyPerUoMTestfield: Boolean)
    begin
        SuppressQtyPerUoMTestfield := WarehouseReceiptLine."Subc. Purchase Line Type" = "Subc. Purchase Line Type"::NotLastOperation;
    end;

    [EventSubscriber(ObjectType::Table, Database::"Warehouse Receipt Line", OnValidateQtyToReceiveOnBeforeUOMMgtValidateQtyIsBalanced, '', false, false)]
    local procedure "Warehouse Receipt Line_OnValidateQtyToReceiveOnBeforeUOMMgtValidateQtyIsBalanced"(var WarehouseReceiptLine: Record "Warehouse Receipt Line"; xWarehouseReceiptLine: Record "Warehouse Receipt Line"; var IsHandled: Boolean)
    begin
        if (WarehouseReceiptLine."Subc. Purchase Line Type" = "Subc. Purchase Line Type"::NotLastOperation) then
            IsHandled := true;
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Whse.-Post Receipt", OnCreatePostedRcptLineOnBeforePutAwayProcessing, '', false, false)]
    local procedure "Whse.-Post Receipt_OnIsReceiptForSubcontracting"(var PostedWhseReceiptLine: Record "Posted Whse. Receipt Line"; var SkipPutAwayProcessing: Boolean)
    begin
        if SkipPutAwayProcessing then
            exit;
        SkipPutAwayProcessing := PostedWhseReceiptLine."Subc. Purchase Line Type" = "Subc. Purchase Line Type"::NotLastOperation;
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Whse.-Post Receipt", OnBeforePostWhseJnlLine, '', false, false)]
    local procedure "Whse.-Post Receipt_OnBeforePostWhseJnlLine"(var PostedWhseReceiptHeader: Record "Posted Whse. Receipt Header"; var PostedWhseReceiptLine: Record "Posted Whse. Receipt Line"; var WhseReceiptLine: Record "Warehouse Receipt Line"; var TempTrackingSpecification: Record "Tracking Specification" temporary; var IsHandled: Boolean)
    begin
        if PostedWhseReceiptLine."Subc. Purchase Line Type" = "Subc. Purchase Line Type"::NotLastOperation then
            IsHandled := true;
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Whse.-Post Receipt", OnPostWhseJnlLineOnAfterInsertWhseItemEntryRelation, '', false, false)]
    local procedure "Whse.-Post Receipt_OnPostWhseJnlLineOnAfterInsertWhseItemEntryRelation"(var PostedWhseRcptHeader: Record "Posted Whse. Receipt Header"; var PostedWhseRcptLine: Record "Posted Whse. Receipt Line"; var TempWhseSplitSpecification: Record "Tracking Specification" temporary; var IsHandled: Boolean; ReceivingNo: Code[20]; PostingDate: Date; var TempWhseJnlLine: Record "Warehouse Journal Line" temporary)
    begin
        if PostedWhseRcptLine."Subc. Purchase Line Type" <> "Subc. Purchase Line Type"::None then
            IsHandled := true;
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Whse.-Post Receipt", OnBeforeCreatePutAwayLine, '', false, false)]
    local procedure "Whse.-Post Receipt_OnIsReceiptIsForSubcontractingNotLastOperation"(PostedWhseReceiptLine: Record "Posted Whse. Receipt Line"; var SkipPutAwayCreationForLine: Boolean)
    begin
        if PostedWhseReceiptLine."Subc. Purchase Line Type" = "Subc. Purchase Line Type"::NotLastOperation then
            SkipPutAwayCreationForLine := true;
    end;

    [EventSubscriber(ObjectType::Table, Database::"Warehouse Receipt Line", OnBeforeOpenItemTrackingLineForPurchLine, '', false, false)]
    local procedure "Warehouse Receipt Line_OnBeforeOpenItemTrackingLineForPurchLine"(PurchaseLine: Record "Purchase Line"; SecondSourceQtyArray: array[3] of Decimal; var SkipCallItemTracking: Boolean)
    var
        ProdOrderLine: Record "Prod. Order Line";
        TrackingSpecification: Record "Tracking Specification";
        ProdOrderLineReserve: Codeunit "Prod. Order Line-Reserve";
        ItemTrackingLines: Page "Item Tracking Lines";
    begin
        if PurchaseLine."Subc. Purchase Line Type" = "Subc. Purchase Line Type"::LastOperation then
            if PurchaseLine.IsSubcontractingLineWithLastOperation(ProdOrderLine) then begin
                ProdOrderLineReserve.InitFromProdOrderLine(TrackingSpecification, ProdOrderLine);
                ItemTrackingLines.SetSourceSpec(TrackingSpecification, ProdOrderLine."Due Date");
                ItemTrackingLines.SetSecondSourceQuantity(SecondSourceQtyArray);
                ItemTrackingLines.RunModal();
                SkipCallItemTracking := true;
            end;
    end;
}