function Add-GSChatCard {
    <#
    .SYNOPSIS
    Creates a Chat Message Card

    .DESCRIPTION
    Creates a Chat Message Card

    .PARAMETER HeaderTitle
    The header title of the card

    .PARAMETER HeaderSubtitle
    The header subtitle of the card

    .PARAMETER HeaderImageStyle
    The header image style of the card

    Available values are:
    * IMAGE
    * AVATAR

    .PARAMETER HeaderImageUrl
    The header image URL of the card

    .PARAMETER CardActions
    The cardActions of the card.

    You must use the function `New-GSChatCardAction` to create cardActions, otherwise this will throw a terminating error.

    .PARAMETER MessageSegment
    Any Chat message segment objects created with functions named `Add-GSChat*` passed through the pipeline or added directly to this parameter as values.

    If section widgets are passed directly to this function, a new section without a SectionHeader will be created and the widgets will be added to it

    .EXAMPLE
    Send-GSChatMessage -Text "Post job report:" -Cards $cards -Webhook (Get-GSChatWebhook JobReports)

    Sends a simple Chat message using the JobReports webhook

    .EXAMPLE
    Add-GSChatTextParagraph -Text "Guys...","We <b>NEED</b> to <i>stop</i> spending money on <b>crap</b>!" |
    Add-GSChatKeyValue -TopLabel "Chocolate Budget" -Content '$5.00' -Icon DOLLAR |
    Add-GSChatKeyValue -TopLabel "Actual Spending" -Content '$5,000,000!' -BottomLabel "WTF" -Icon AIRPLANE |
    Add-GSChatImage -ImageUrl "https://media.tenor.com/images/f78545a9b520ecf953578b4be220f26d/tenor.gif" -LinkImage |
    Add-GSChatCardSection -SectionHeader "Dollar bills, y'all" -OutVariable sect1 | 
    Add-GSChatButton -Text "Launch nuke" -OnClick (Add-GSChatOnClick -Url "https://github.com/scrthq/PSGSuite") -Verbose -OutVariable button1 | 
    Add-GSChatButton -Text "Unleash hounds" -OnClick (Add-GSChatOnClick -Url "https://admin.google.com/?hl=en&authuser=0") -Verbose -OutVariable button2 | 
    Add-GSChatCardSection -SectionHeader "What should we do?" -OutVariable sect2 | 
    Add-GSChatCard -HeaderTitle "Makin' moves with" -HeaderSubtitle "DEM GOODIES" -OutVariable card |
    Add-GSChatTextParagraph -Text "This message sent by <b>PSGSuite</b> via WebHook!" | 
    Add-GSChatCardSection -SectionHeader "Additional Info" -OutVariable sect2 | 
    Send-GSChatMessage -Text "Got that report, boss:" -FallbackText "Mistakes have been made..." -Webhook ReportRoom

    This example shows the pipeline capabilities of the Chat functions in PSGSuite. Starting from top to bottom:
        1. Add a TextParagraph widget
        2. Add a KeyValue with an icon
        3. Add another KeyValue with a different icon
        4. Add an image and create an OnClick event to open the image's URL by using the -LinkImage parameter
        5. Add a new section to encapsulate the widgets sent through the pipeline before it
        6. Add a TextButton that opens the PSGSuite GitHub repo when clicked
        7. Add another TextButton that opens Google Admin Console when clicked
        8. Wrap the 2 buttons in a new Section to divide the content
        9. Wrap all widgets and sections in the pipeline so far in a Card
        10. Add a new TextParagraph as a footer to the message
        11. Wrap that TextParagraph in a new section
        12. Send the message and include FallbackText that's displayed in the mobile notification. Since the final TextParagraph and Section are not followed by a new Card addition, Send-GSChatMessage will create a new Card just for the remaining segments then send the completed message via Webhook. The Webhook short-name is used to reference the full URL stored in the encrypted Config so it's not displayed in the actual script.

    .EXAMPLE
    Get-Service | Select-Object -First 5 | ForEach-Object {
        Add-GSChatKeyValue -TopLabel $_.DisplayName -Content $_.Status -BottomLabel $_.Name -Icon TICKET
    } | Add-GSChatCardSection -SectionHeader "Top 5 Services" | Send-GSChatMessage -Text "Service Report:" -FallbackText "Service Report" -Webhook Reports

    This gets the first 5 Services returned by Get-Service, creates KeyValue widgets for each, wraps it in a section with a header, then sends it to the Reports Webhook
    #>
    Param
    (
        [parameter(Mandatory = $false,Position = 0)]
        [String]
        $HeaderTitle,
        [parameter(Mandatory = $false)]
        [String]
        $HeaderSubtitle,
        [parameter(Mandatory = $false)]
        [ValidateSet('IMAGE','AVATAR')]
        [String]
        $HeaderImageStyle,
        [parameter(Mandatory = $false)]
        [String]
        $HeaderImageUrl,
        [parameter(Mandatory = $false)]
        [ValidateScript({
            $allowedTypes = "PSGSuite.Chat.Message.Card.CardAction"
            foreach ($item in $_) {
                if ([string]$($item.PSTypeNames) -match "($(($allowedTypes|ForEach-Object{[RegEx]::Escape($_)}) -join '|'))") {
                    $true
                }
                else {
                    throw "This parameter only accepts the following types: $($allowedTypes -join ", "). The current types of the value are: $($item.PSTypeNames -join ", ")."
                }
            }
        })]
        [Object[]]
        $CardActions,
        [parameter(Mandatory = $false,ValueFromPipeline = $true)]
        [Alias('InputObject')]
        [ValidateScript( {
            $allowedTypes = "PSGSuite.Chat.Message.Card.Section","PSGSuite.Chat.Message.Card","PSGSuite.Chat.Message.Card.CardAction","PSGSuite.Chat.Message.Card.Section.TextParagraph","PSGSuite.Chat.Message.Card.Section.Button","PSGSuite.Chat.Message.Card.Section.Image","PSGSuite.Chat.Message.Card.Section.KeyValue"
            foreach ($item in $_) {
                if ([string]$($item.PSTypeNames) -match "($(($allowedTypes|ForEach-Object{[RegEx]::Escape($_)}) -join '|'))") {
                    $true
                }
                else {
                    throw "This parameter only accepts the following types: $($allowedTypes -join ", "). The current types of the value are: $($item.PSTypeNames -join ", ")."
                }
            }
        })]
        [Object[]]
        $MessageSegment
    )
    Begin {
        $cardObject = @{
            Webhook = @{}
            SDK = (New-Object 'Google.Apis.HangoutsChat.v1.Data.Card')
        }
        $addlSectionWidgets = @()
        foreach ($key in $PSBoundParameters.Keys) {
            switch ($key) {
                HeaderTitle {
                    if (!$cardObject['Webhook']['header']) {
                        $cardObject['Webhook']['header'] = @{}
                    }
                    $cardObject['Webhook']['header']['title'] = $PSBoundParameters[$key]
                    if (!$cardObject['SDK'].Header) {
                        $cardObject['SDK'].Header = New-Object 'Google.Apis.HangoutsChat.v1.Data.CardHeader'
                    }
                    $cardObject['SDK'].Header.Title = $PSBoundParameters[$key]
                }
                HeaderSubtitle {
                    if (!$cardObject['Webhook']['header']) {
                        $cardObject['Webhook']['header'] = @{}
                    }
                    $cardObject['Webhook']['header']['subtitle'] = $PSBoundParameters[$key]
                    if (!$cardObject['SDK'].Header) {
                        $cardObject['SDK'].Header = New-Object 'Google.Apis.HangoutsChat.v1.Data.CardHeader'
                    }
                    $cardObject['SDK'].Header.Subtitle = $PSBoundParameters[$key]
                }
                HeaderImageStyle {
                    if (!$cardObject['Webhook']['header']) {
                        $cardObject['Webhook']['header'] = @{}
                    }
                    $cardObject['Webhook']['header']['imageStyle'] = $PSBoundParameters[$key]
                    if (!$cardObject['SDK'].Header) {
                        $cardObject['SDK'].Header = New-Object 'Google.Apis.HangoutsChat.v1.Data.CardHeader'
                    }
                    $cardObject['SDK'].Header.ImageStyle = $PSBoundParameters[$key]
                }
                HeaderImageUrl {
                    if (!$cardObject['Webhook']['header']) {
                        $cardObject['Webhook']['header'] = @{}
                    }
                    $cardObject['Webhook']['header']['imageUrl'] = $PSBoundParameters[$key]
                    if (!$cardObject['SDK'].Header) {
                        $cardObject['SDK'].Header = New-Object 'Google.Apis.HangoutsChat.v1.Data.CardHeader'
                    }
                    $cardObject['SDK'].Header.ImageUrl = $PSBoundParameters[$key]
                }
                CardActions {
                    if (!$cardObject['Webhook']['cardActions']) {
                        $cardObject['Webhook']['cardActions'] = @()
                    }
                    foreach ($cardAction in $CardActions) {
                        $cardObject['Webhook']['cardActions'] += $cardAction['Webhook']
                    }
                    if (!$cardObject['SDK'].CardActions) {
                        $cardObject['SDK'].CardActions = New-Object 'System.Collections.Generic.List[Google.Apis.HangoutsChat.v1.Data.CardAction]'
                    }
                    foreach ($cardAction in $CardActions) {
                        $cardObject['SDK'].CardActions.Add($cardAction['SDK']) | Out-Null
                    }
                }
            }
        }
    }
    Process {
        foreach ($segment in $MessageSegment) {
            if ($segment.PSTypeNames[0] -eq 'PSGSuite.Chat.Message.Card') {
                $segment
            }
            elseif ($segment.PSTypeNames[0] -in @("PSGSuite.Chat.Message.Card.Section.TextParagraph","PSGSuite.Chat.Message.Card.Section.Button","PSGSuite.Chat.Message.Card.Section.Image","PSGSuite.Chat.Message.Card.Section.KeyValue")) {
                $addlSectionWidgets += $segment
            }
            elseif ($segment.PSTypeNames[0] -eq 'PSGSuite.Chat.Message.Card.CardAction') {
                if (!$cardObject['Webhook']['cardActions']) {
                    $cardObject['Webhook']['cardActions'] = @()
                }
                $cardObject['Webhook']['cardActions'] += $segment['Webhook']
                if (!$cardObject['SDK'].CardActions) {
                    $cardObject['SDK'].CardActions = New-Object 'System.Collections.Generic.List[Google.Apis.HangoutsChat.v1.Data.CardAction]'
                }
                $cardObject['SDK'].CardActions.Add($segment['SDK']) | Out-Null
            }
            elseif ($segment.PSTypeNames[0] -eq 'PSGSuite.Chat.Message.Card.Section') {
                if (!$cardObject['Webhook']['sections']) {
                    $cardObject['Webhook']['sections'] = @()
                }
                $cardObject['Webhook']['sections'] += $segment['Webhook']
                if (!$cardObject['SDK'].Sections) {
                    $cardObject['SDK'].Sections = New-Object 'System.Collections.Generic.List[Google.Apis.HangoutsChat.v1.Data.Section]'
                }
                $cardObject['SDK'].Sections.Add($segment['SDK']) | Out-Null
            }
        }
    }
    End {
        if($addlSectionWidgets) {
            $newWidgetStack = @()
            for ($i = 0;$i -lt $addlSectionWidgets.Count;$i++) {
                if ($newWidgetStack -and ($addlSectionWidgets[$i].PSTypeNames[0] -eq 'PSGSuite.Chat.Message.Card.Section.Button') -and ($newWidgetStack[-1].PSTypeNames[0] -eq 'PSGSuite.Chat.Message.Card.Section.Button')) {
                    $newWidgetStack[-1]['Webhook']['buttons'] += $addlSectionWidgets[$i]['Webhook']['buttons'][0]
                    $newWidgetStack[-1]['SDK'].Buttons.Add($addlSectionWidgets[$i]['SDK'].Buttons[0]) | Out-Null
                }
                else {
                    $newWidgetStack += $addlSectionWidgets[$i]
                }
            }
            $addlSection = $newWidgetStack | Add-GSChatCardSection
            if (!$cardObject['Webhook']['sections']) {
                $cardObject['Webhook']['sections'] = @()
            }
            $cardObject['Webhook']['sections'] += $addlSection['Webhook']
            if (!$cardObject['SDK'].Sections) {
                $cardObject['SDK'].Sections = New-Object 'System.Collections.Generic.List[Google.Apis.HangoutsChat.v1.Data.Section]'
            }
            $cardObject['SDK'].Sections.Add($addlSection['SDK']) | Out-Null
        }
        [void]$cardObject.PSObject.TypeNames.Insert(0,'PSGSuite.Chat.Message.Card')
        return $cardObject
    }
}