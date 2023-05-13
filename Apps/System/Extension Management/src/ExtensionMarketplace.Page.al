﻿// ------------------------------------------------------------------------------------------------
// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License. See License.txt in the project root for license information.
// ------------------------------------------------------------------------------------------------

/// <summary>
/// Shows the Extension Marketplace.
/// </summary>
page 2502 "Extension Marketplace"
{
    Caption = 'Extension Marketplace';
    PageType = Card;
    ApplicationArea = All;
    UsageCategory = Administration;
    Editable = false;

    layout
    {
        area(Content)
        {
            usercontrol(Marketplace; WebPageViewerExtMgmt)
            {
                ApplicationArea = Basic, Suite;
                trigger ControlAddInReady(callbackUrl: Text)
                var
                    MarketplaceUrl: Text;
                begin
                    if AppsourceUrl <> '' then
                        MarketplaceUrl := AppsourceUrl
                    else
                        MarketplaceUrl := ExtensionMarketplace.GetMarketplaceEmbeddedUrl();
                    CurrPage.Marketplace.SubscribeToEvent('message', MarketplaceUrl);
                    CurrPage.Marketplace.Navigate(MarketplaceUrl);
                end;

                trigger DocumentReady()
                begin
                end;

                trigger Callback(data: Text);
                begin
                    if TryGetMsgType(data) then
                        PerformAction(MessageType);
                end;

                trigger Refresh(callbackUrl: Text);
                var
                    MarketplaceUrl: Text;
                begin
                    MarketplaceUrl := ExtensionMarketplace.GetMarketplaceEmbeddedUrl();
                    CurrPage.Marketplace.SubscribeToEvent('message', MarketplaceUrl);
                    CurrPage.Marketplace.Navigate(MarketplaceUrl);
                end;
            }

        }
    }

    local procedure PerformAction(ActionName: Text);
    var
        applicationId: Text;
        ActionOption: Option acquireApp;
    begin
        if EVALUATE(ActionOption, ActionName) then
            if ActionOption = ActionOption::acquireApp then begin
                TelemetryUrl := ExtensionMarketplace.GetTelementryUrlFromData(JObject);
                applicationId := ExtensionMarketplace.GetApplicationIdFromData(JObject);
                ExtensionMarketplace.InstallAppsourceExtensionWithRefreshSession(applicationId, TelemetryUrl);
            end;
    end;

    [TryFunction]
    local procedure TryGetMsgType(data: Text);
    begin
        JObject := JObject.Parse(data);
        MessageType := ExtensionMarketplace.GetMessageType(JObject);
    end;

    internal procedure SetAppsourceUrl(Url: Text)
    begin
        AppsourceUrl := Url;
    end;

    var
        ExtensionMarketplace: Codeunit "Extension Marketplace";
        JObject: DotNet JObject;
        MessageType: Text;
        TelemetryUrl: Text;
        AppsourceUrl: Text;
}
