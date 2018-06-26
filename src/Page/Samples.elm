module Page.Samples exposing (Model, Msg(..), ExternalMsg(..), init, update, view)

import Data.Sample as Sample exposing (Sample, Investigator, JsonType(..), SearchResult, SearchParamsResult)
import Data.Session as Session exposing (Session)
import Data.Cart
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (onCheck, onInput, onClick, onDoubleClick)
import Dialog
import MultiSelect as Multi
import Http
import List exposing (map)
import List.Extra
import Dict exposing (Dict)
import Set exposing (Set)
import String.Extra as SE
import Page.Error as Error exposing (PageLoadError)
import RemoteData exposing (RemoteData(..), WebData)
import Request.Sample
import Route
import String exposing (join)
import Table exposing (defaultCustomizations)
import Task exposing (Task)
import Time exposing (Time)
import Util exposing ((=>), truncate, capitalize)
import View.Cart as Cart
import View.Sample
import View.FilterButtonGroup
import View.SearchableDropdown2
import View.Widgets
import View.Spinner exposing (spinner)



---- MODEL ----


type alias Model =
    { pageTitle : String
    , samples : List Sample
    , user_id : Maybe Int
    , tableState : Table.State
    , query : String
    , sampleTypeRestriction : List String
    , cart : Cart.Model
    , params : Dict String String
    , restrictedParams : Dict String String
    , selectedParams : List ( String, String )
    , possibleOptionValues : Dict String (List JsonType)
    , optionValues : Dict String (List String)
    , optionUnits : Dict String String
    , searchResults : WebData (List SearchResult)
    , doSearch : Bool
    , searchStartTime : Time
    , isSearching : Bool
    , attrDropdownState : View.SearchableDropdown2.State
    , selectedRowId : Int
    , permFilterType : String
    , showInfoDialog : Bool
    }


init : Session -> Task PageLoadError Model
init session =
    let
        loadSearchParams =
            Request.Sample.getParams |> Http.toTask

        user_id =
            Maybe.map .user_id session.user
    in
    loadSearchParams |> Task.andThen
        (\params ->
            let
                dropdownResults =
                    params |> Dict.toList |> List.map (\(k,v) -> (k, prettyName k))
            in
            Task.succeed
            { pageTitle = "Samples"
            , samples = []
            , user_id = user_id
            , tableState = Table.initialSort "Name"
            , query = ""
            , sampleTypeRestriction = []
            , cart = (Cart.init session.cart Cart.Editable)
            , params = params
            , restrictedParams = Dict.empty
            , selectedParams = []
            , possibleOptionValues = Dict.empty
            , optionValues = Dict.empty
            , optionUnits = Dict.empty
            , searchResults = NotAsked
            , doSearch = True
            , searchStartTime = 0
            , isSearching = True
            , attrDropdownState = View.SearchableDropdown2.State False "" dropdownResults Nothing
            , selectedRowId = 0
            , permFilterType = "All"
            , showInfoDialog = False
            }
        )
        |> Task.mapError Error.handleLoadError


-- UPDATE --


type Msg
    = CartMsg Cart.Msg
    | SetQuery String
    | SelectType String Bool
    | SetTableState Table.State
    | SetSession Session
    | AddParamOption String
    | RemoveOption String
    | UpdateOptionValue String String
    | UpdateMultiOptionValue String (List String)
    | UpdatePossibleOptionValues (Result Http.Error SearchParamsResult)
    | SetStartTime Time
    | DelayedSearch Time
    | UpdateSearchResults (WebData (List SearchResult))
    | UpdateSamples (Result Http.Error (List Sample))
    | SetAttrName String
    | SelectAttr String String
    | ToggleAttr
    | FilterPermType String
    | OpenInfoDialog Int
    | CloseInfoDialog


type ExternalMsg
    = NoOp
    | SetCart Data.Cart.Cart


update : Session -> Msg -> Model -> ( ( Model, Cmd Msg ), ExternalMsg )
update session msg model =
    let
        dropdownState =
            model.attrDropdownState

        setStartTime =
            Task.perform SetStartTime Time.now
    in
    case msg of
        CartMsg subMsg ->
            let
                ( ( newCart, subCmd ), msgFromPage ) =
                    Cart.update session subMsg model.cart
            in
            { model | cart = newCart } => Cmd.map CartMsg subCmd => SetCart newCart.cart

        SetQuery newQuery ->
            { model | query = newQuery } => Cmd.none => NoOp

        SetTableState newState ->
            { model | tableState = newState } => Cmd.none => NoOp

        SelectType value bool ->
            let
                curOptions =
                    model.sampleTypeRestriction

                newOpts =
                    case bool of
                        True ->
                            List.sort (value :: curOptions)

                        False ->
                            List.filter ((/=) value) curOptions
            in
            { model | sampleTypeRestriction = newOpts } => Cmd.none => NoOp

        SetSession newSession ->
            let
                newCart =
                    Cart.init newSession.cart Cart.Editable

                (subModel, cmd) =
                    Cart.update newSession (Cart.SetSession newSession) model.cart
            in
            { model | cart = newCart } => Cmd.none => NoOp

        AddParamOption opt ->
            let
                req =
                    Request.Sample.getParamValues opt model.optionValues model.possibleOptionValues model.params |> Http.toTask
            in
            { model | selectedParams = addSelectedParam model opt, isSearching = True }
            => Task.attempt UpdatePossibleOptionValues req
            => NoOp

        RemoveOption opt ->
            { model
                | selectedParams = rmParam model.selectedParams opt
                , optionValues = rmOptionValue model.optionValues opt
                , doSearch = True, isSearching = True
            } => Cmd.none => NoOp

        SetStartTime time ->
            { model | searchStartTime = time } => Cmd.none => NoOp

        DelayedSearch time ->
            if model.doSearch then
                if model.selectedParams == [] then
                    if model.samples == [] then
                        { model | doSearch = False } => Task.attempt UpdateSamples (Request.Sample.list session.token |> Http.toTask) => NoOp
                    else
                        { model | doSearch = False, isSearching = False, searchResults = NotAsked } => Cmd.none => NoOp
                else if time - model.searchStartTime >= 500 * Time.millisecond then
                    let
                        cmd =
                            Request.Sample.search model.optionValues model.possibleOptionValues model.params |> Cmd.map UpdateSearchResults
                    in
                    { model | doSearch = False, isSearching = True } => cmd => NoOp
                else
                    model => Cmd.none => NoOp
            else
                model => Cmd.none => NoOp

        UpdateOptionValue opt val ->
            { model
                | optionValues = Dict.insert opt [ val ] model.optionValues
                , doSearch = True
            }
            => setStartTime
            => NoOp

        UpdateMultiOptionValue opt vals ->
            { model
                | optionValues = Dict.insert opt vals model.optionValues
                , doSearch = True
            }
            => setStartTime
            => NoOp

        UpdateSearchResults response ->
            { model
                | searchResults = response
                , restrictedParams = mkRestrictedParams model.params response
                -- , restrictedOptionValues = mkRestrictedOptionValues response
                , isSearching = False
            }
            => Cmd.none
            => NoOp

        UpdateSamples (Ok samples) ->
            { model | samples = samples, isSearching = False } => Cmd.none => NoOp

        UpdateSamples (Err error) ->
            model => Cmd.none => NoOp

        UpdatePossibleOptionValues (Ok response) ->
            let
                opt =
                    response.param

                (minVal, maxVal) =
                    maxMinForOpt response.values

                dataType =
                    case Dict.get opt (Dict.fromList model.selectedParams) of
                        Nothing -> ""

                        Just dataType -> dataType

                optionValues =
                    case dataType of
                        "number" ->
                            Dict.fromList [ (("max__" ++ opt), [maxVal]), (("min__" ++ opt) , [minVal]) ]

                        _ -> Dict.fromList []

                newModel = { model
                                | possibleOptionValues = Dict.insert opt response.values model.possibleOptionValues
                                , optionValues = Dict.union optionValues model.optionValues
                                , optionUnits = Dict.insert opt response.units model.optionUnits
                                , doSearch = True
                            }
            in
            newModel => Cmd.none => NoOp

        UpdatePossibleOptionValues (Err err) ->
            model => Cmd.none => NoOp

        SetAttrName name ->
            let
                params =
                    if Dict.isEmpty model.restrictedParams || model.selectedParams == [] then
                        model.params
                    else
                        model.restrictedParams

                alreadySelected =
                    List.map Tuple.first model.selectedParams |> Set.fromList

                -- mdb added 2/14/18 - list of curated metadata terms from Alise
--              curated =
--                  Set.fromList ["environment__biome", "specimen__domain_of_life", "location__latitude", "location__longitude", "miscellaneous__principle_investigator", "miscellaneous__project_id"]

                attrValue =
                    String.toLower dropdownState.value

                filteredParams =
                    if attrValue == "" then
                        params
                    else
                        params
                            |> Dict.filter (\k v -> String.contains attrValue (String.toLower k)) -- filter on search string
                            |> Dict.filter (\k v -> not (Set.member k alreadySelected)) -- filter on already selected
--                          |> Dict.filter (\k v -> (Set.member k curated)) -- mdb added 2/14/18 - only show curated terms

                results =
                    filteredParams |> Dict.toList |> List.map (\(k,v) -> (k, prettyName k))
            in
            { model | attrDropdownState = { dropdownState | value = name, results = results } } => Cmd.none => NoOp

        SelectAttr id name ->
            let
                ((newModel, newCmd), extMsg) =
                    update session (AddParamOption id) model
            in
            { newModel | attrDropdownState = { dropdownState | value = "", show = False } } => newCmd => extMsg

        ToggleAttr ->
            { model | attrDropdownState = { dropdownState | show = not dropdownState.show } } => Cmd.none => NoOp

        FilterPermType filterType ->
            { model | permFilterType = filterType, selectedRowId = 0 } => Cmd.none => NoOp

        OpenInfoDialog id ->
            { model | showInfoDialog = True, selectedRowId = id } => Cmd.none => NoOp

        CloseInfoDialog ->
            { model | showInfoDialog = False } => Cmd.none => NoOp


config : Cart.Model -> Int -> Table.Config Sample Msg
config cart selectedRowId =
    Table.customConfig
        { toId = toString << .sample_id
        , toMsg = SetTableState
        , columns =
            [ projectColumn
            , nameColumn
            , Table.stringColumn "Type" .sample_type
            , addToCartColumn cart
            ]
        , customizations =
            { defaultCustomizations | tableAttrs = toTableAttrs, rowAttrs = toRowAttrs selectedRowId }
        }


toTableAttrs : List (Attribute Msg)
toTableAttrs =
    [ attribute "class" "table table-hover" ]


toRowAttrs : Int -> Sample -> List (Attribute Msg)
toRowAttrs selectedRowId data =
    [ onDoubleClick (OpenInfoDialog data.sample_id) ]



-- VIEW --


view : Model -> Html Msg
view model =
    div []
        ((case model.searchResults of
            NotAsked ->
                showAll model

            Loading ->
                text "Loading ..."

            Failure e ->
                text (toString e)

            Success data ->
                case model.selectedParams of
                    [] ->
                        showAll model

                    _ ->
                        showSearchResults model data
        ) ::
        [ Dialog.view
           (if model.showInfoDialog then
               Just (infoDialogConfig model)
            else
                Nothing
           )
        ])


showSearchResults : Model -> List SearchResult -> Html Msg
showSearchResults model results =
    let
        lowerQuery =
            String.toLower model.query

        mkTh fld =
            th [] [ text (prettyName fld) ]

        fieldNames =
            List.map Tuple.first model.selectedParams
                |> List.map addUnits

        addUnits param =
            let
                units =
                    Dict.get param model.optionUnits |> Maybe.withDefault ""
            in
            if units == "" then
                param
            else
                param ++ " (" ++ units  ++ ")"

        headerRow =
            [ tr [] ((List.map mkTh ("specimen__project_name" :: "specimen__sample_name" :: "specimen__sample_type" :: fieldNames)) ++ [cartTh]) ]

        checkPerms permFilterType userId users =
            if permFilterType == "All" then
                True
            else -- Mine
                case userId of
                    Nothing ->
                        False

                    Just id ->
                        List.map .user_id users |> List.member id

        catFields result =
            List.intersperse " "
                [ getVal "specimen__sample_name" result.attributes
                , getVal "specimen__project_name" result.attributes
                ]
            |> String.concat
            |> String.toLower

        filterOnQuery result =
            String.contains lowerQuery (catFields result)

        filteredSamples =
            results
                |> List.filter filterOnQuery
                |> List.filter filterOnType

        acceptableSamples =
            filteredSamples
                |> List.filter (\result -> checkPerms model.permFilterType model.user_id result.users)

        resultRows =
            acceptableSamples
                |> List.map (.attributes >> mkResultRow model.selectedRowId model.cart model.selectedParams)

        filterOnType result =
            if model.sampleTypeRestriction == [] then
                True
            else
                List.member (getVal "specimen__sample_type" result.attributes |> capitalize) model.sampleTypeRestriction

        sampleIdFromResult result =
            case String.toInt (getVal "specimen__sample_id" result) of
                Ok sampleId ->
                    sampleId

                Err _ ->
                    0

        addAllBtn =
            acceptableSamples
                |> List.map (.attributes >> sampleIdFromResult)
                |> List.filter (\id -> id /= 0)
                |> Cart.addAllToCartButton model.cart Nothing
                |> Html.map CartMsg

        cartTh =
            th [ class "nowrap" ]
                [ text "Cart "
                , br [] []
                , addAllBtn
                ]

        body =
            if model.isSearching then
                spinner
            else
                if results == [] then
                    noResults
                else if model.query /= "" && (filteredSamples == [] || acceptableSamples == []) then
                    noResults
                else if acceptableSamples == [] then
                    noResults --noResultsLoggedIn model.user_id
                else
                   div [ class "container" ]
                       [ div [ class "row" ]
                           [ table [ class "table table-hover" ]
                               [ tbody [] (headerRow ++ resultRows) ]
                           ]
                       ]
    in
    div [ class "container" ]
        [ div [ class "row" ]
            [ div [ class "page-header" ]
                [ h1 []
                    [ text (model.pageTitle ++ " ")
                    , View.Widgets.counter (List.length acceptableSamples)
                    , small [ class "right" ] [ input [ placeholder "Search", onInput SetQuery ] [] ]
                    ]
                ]
            , div [ class "panel panel-default" ]
                [ div [ class "panel-body" ]
                    [ viewTypes model.samples
                    , viewAccessFilter model.permFilterType
                    , searchView model
                    ]
                ]
            , body
            ]
        ]


showAll : Model -> Html Msg
showAll model =
    let
        lowerQuery =
            String.toLower model.query

        catFields sample =
            String.concat
                (List.intersperse " "
                    [ sample.sample_name
                    , sample.project.project_name
                    ]
                )
                |> String.toLower

        checkPerms permFilterType userId project =
            case permFilterType of
                "All" ->
                    True

                _ ->
                    case userId of
                        Nothing ->
                            False

                        Just id ->
                            (List.map .user_id project.users |> List.member id) ||
                            (List.map .users project.project_groups |> List.concat |> List.map .user_id |> List.member id)

        filter sample =
            (String.contains lowerQuery (catFields sample))
                && (checkPerms model.permFilterType model.user_id sample.project)

        filteredSamples =
            List.filter filter model.samples

        acceptableSamples =
            case List.length model.sampleTypeRestriction of
                0 ->
                    filteredSamples

                _ ->
                    List.filter
                        (\v ->
                            List.member v.sample_type
                                model.sampleTypeRestriction
                        )
                        filteredSamples

        body =
            if model.isSearching then
                spinner
            else
                if model.query /= "" && (filteredSamples == [] || acceptableSamples == []) then
                    noResults
                else if acceptableSamples == [] then
                    noResultsLoggedIn model.user_id
                else
                   div [ class "container" ]
                       [ div [ class "row" ]
                           [ Table.view (config model.cart model.selectedRowId) model.tableState acceptableSamples ]
                       ]
    in
    div [ class "container" ]
        [ div [ class "row" ]
            [ div [ class "page-header" ]
                [ h1 []
                    [ text (model.pageTitle ++ " ")
                    , View.Widgets.counter (List.length acceptableSamples)
                    , small [ class "right" ] [ input [ placeholder "Search", onInput SetQuery ] [] ]
                    ]
                ]
            ]
        , div [ class "row" ]
            [ div [ class "panel panel-default" ]
                [ div [ class "panel-body", classList [("disabled", model.isSearching)] ]
                    [ viewTypes model.samples
                    , viewAccessFilter model.permFilterType
                    , searchView model
                    ]
                ]
            ]
        , div [ class "row" ]
            [ body ]
        ]


noResults : Html Msg
noResults =
    div [ class "italic gray", style [("font-size", "2em")] ] [ text "No results" ]


noResultsLoggedIn : Maybe Int -> Html Msg
noResultsLoggedIn userId =
    if userId /= Nothing then
        div [ class "well" ]
            [ p [] [ text "You don't have any samples yet." ]
            , p []
                [ text "To add a sample, go to the "
                , a [ Route.href Route.Dashboard ] [ text "Dashboard" ]
                , text ", select 'Projects', and click 'New'."
                ]
            ]
    else
        div [ class "well" ]
            [ p []
                [ text "Please "
                , a [ Route.href Route.Login ] [ text "login" ]
                , text " to see your samples."
                ]
            ]


viewTypes : List Sample -> Html Msg
viewTypes samples =
    let
        sampleTypes =
            List.map (\x -> x.sample_type) samples
                |> List.filter ((/=) "")
                |> List.map capitalize
                |> List.sort
                |> List.Extra.unique
    in
    if List.length sampleTypes == 0 then
        text ""
    else
        fieldset []
            (span [ class "bold" ] [ text "Types: " ]
                :: List.map mkCheckbox sampleTypes
            )


mkCheckbox : String -> Html Msg
mkCheckbox val =
    span [ style [("padding-left", "1em")]]
        [ input [ type_ "checkbox", onCheck (SelectType val) ] []
        , text (" " ++ val)
        ]


searchView : Model -> Html Msg
searchView model =
    div []
        [ div [ class "bold" ] [ text "Attributes:" ]
        , div [] [ mkOptionTable model ]
        , div [] [ mkParamsSelect model ]
        ]


viewAccessFilter : String -> Html Msg
viewAccessFilter permFilterType =
    div []
        [ span [ class "bold" ] [ text "Access: " ]
        , View.FilterButtonGroup.view permissionFilterConfig permFilterType
        ]


permissionFilterConfig : View.FilterButtonGroup.Config Msg
permissionFilterConfig =
    View.FilterButtonGroup.Config [ "All", "Mine" ] FilterPermType


nameColumn : Table.Column Sample Msg
nameColumn =
    Table.veryCustomColumn
        { name = "Sample"
        , viewData = nameLink
        , sorter = Table.increasingOrDecreasingBy (String.toLower << .sample_name)
        }


nameLink : Sample -> Table.HtmlDetails Msg
nameLink sample =
    Table.HtmlDetails []
        [ a [ Route.href (Route.Sample sample.sample_id) ]
            [ text <| Util.truncate sample.sample_name ]
        ]


projectColumn : Table.Column Sample Msg
projectColumn =
    Table.veryCustomColumn
        { name = "Project"
        , viewData = projectLink
        , sorter = Table.increasingOrDecreasingBy (.project >> .project_name >> String.toLower)
        }


projectLink : Sample -> Table.HtmlDetails Msg
projectLink sample =
    Table.HtmlDetails []
        [ a [ Route.href (Route.Project sample.project_id) ]
            [ text <| Util.truncate sample.project.project_name ]
        ]


addToCartColumn : Cart.Model -> Table.Column Sample Msg
addToCartColumn cart =
    Table.veryCustomColumn
        { name = "Cart"
        , viewData = (\sample -> addToCartButton cart sample)
        , sorter = Table.unsortable
        }


addToCartButton : Cart.Model -> Sample -> Table.HtmlDetails Msg
addToCartButton cart sample =
    Table.HtmlDetails []
        [ Cart.addToCartButton cart sample.sample_id |> Html.map CartMsg
        ]



addSelectedParam : Model -> String -> List ( String, String )
addSelectedParam model optionName =
    case Dict.get optionName model.params of
        Just dataType ->
            model.selectedParams ++ [ ( optionName, dataType ) ]

        _ ->
            model.selectedParams


mkParamsSelect : Model -> Html Msg
mkParamsSelect model =
    div [ class "padded", style [("padding-left","1em")] ]
        [ View.SearchableDropdown2.view attrDropdownConfig model.attrDropdownState ]


attrDropdownConfig : View.SearchableDropdown2.Config Msg Msg Msg
attrDropdownConfig =
    { placeholder = "Search for an attribute to add "
    , autofocus = False
    , inputMsg = SetAttrName
    , selectMsg = SelectAttr
    , toggleMsg = ToggleAttr
    , className = "search-dropdown"
    }


attrDropdownInit : Dict String String -> List (String, String)
attrDropdownInit params =
    params |> Dict.toList |> List.map (\(k,v) -> (k, prettyName k))


prettyName : String -> String
prettyName s =
    let
        parts =
            String.split "__" s

        ( category, name ) =
            case parts of
                first :: rest :: [] ->
                    ( first, rest )

                _ ->
                    ( "NA", String.join "_" parts )

        nameParts =
            String.split "_" name
    in
    case s of
        "specimen__sample_name" -> "Sample"

        "specimen__project_name" -> "Project"

        "specimen__sample_type" -> "Type"

        _ ->
            SE.toSentenceCase category
                ++ ": "
                ++ String.join " " (List.map SE.toSentenceCase nameParts)


mkOptionTable : Model -> Html Msg
mkOptionTable model =
    let
        rows =
            List.map (mkOptionRow model.optionValues model.optionUnits model.possibleOptionValues) model.selectedParams
    in
    if rows == [] then
        text ""
    else
        table [ style [ ("width", "95%"), ("margin-left", "2em"), ("padding", "4px"), ("background-color", "#f0f0f0") ] ] rows


unpackJsonType : JsonType -> String
unpackJsonType v =
    case v of
        FloatType n ->
            toString n

        IntType n ->
            toString n

        StrType s ->
            s

        ValueType x ->
            toString x


mkOptionRow : Dict String (List String) -> Dict String String -> Dict String (List JsonType) -> ( String, String ) -> Html Msg
mkOptionRow optionValues optionUnits possibleOptionValues ( optionName, dataType ) =
    let
        units =
            Dict.get optionName optionUnits |> Maybe.withDefault ""

        unitsStr =
            if units == "" then
                ""
            else
                " (" ++ units ++ ")"

        title =
            [ th [] [ (prettyName optionName) ++ unitsStr |> text ] ]

        vals =
            Dict.get optionName possibleOptionValues |> Maybe.withDefault []

        (minVal, maxVal) =
            maxMinForOpt (Dict.get optionName possibleOptionValues |> Maybe.withDefault [])

        strVals =
            let
                mkOption s =
                    Html.option [ value s ] [ text s ]
            in
            if List.length vals > 1000 then
                input
                    [ onInput (UpdateOptionValue optionName)
                    , type_ "text"
                    , placeholder dataType
                    ]
                    []
            else
                mkMultiSelect optionName vals

        minName =
            "min__" ++ optionName

        maxName =
            "max__" ++ optionName

        curMinVal =
            Dict.get minName optionValues |> Maybe.withDefault [] |> List.head |> Maybe.withDefault ""

        curMaxVal =
            Dict.get maxName optionValues |> Maybe.withDefault [] |> List.head |> Maybe.withDefault ""

        el =
            case dataType of
                "number" ->
                    [ td [ onInput (UpdateOptionValue minName) ]
                        [ text "Min: "
                        , input [ type_ "text", name minName, placeholder minVal, value (if curMinVal == minVal then "" else curMinVal) ] []
                        ]
                    , td [ onInput (UpdateOptionValue maxName) ]
                        [ text "Max: "
                        , input [ type_ "text", name maxName, placeholder maxVal, value (if curMaxVal == maxVal then "" else curMaxVal) ] []
                        ]
                    ]

                _ ->
                    [ td [] [ strVals ]
                    , td [] []
                    ]

        buttons =
            [ td [] [ button [ class "btn btn-default btn-sm", onClick (RemoveOption optionName) ] [ text "Remove" ] ]
            ]
    in
    tr [ class "padded" ] (title ++ el ++ buttons)


maxMinForOpt : List JsonType -> (String, String)
maxMinForOpt vals =
    let
        minVal =
            case List.take 1 vals of
                x :: [] ->
                    unpackJsonType x

                _ ->
                    ""

        maxVal =
            case List.drop (List.length vals - 1) vals of
                x :: [] ->
                    unpackJsonType x

                _ ->
                    ""
   in
   (minVal, maxVal)


mkMultiSelect : String -> List JsonType -> Html Msg
mkMultiSelect optionName vals =
    let
        strings =
            List.map unpackJsonType vals

        items =
            List.map (\s -> { value = s, text = s, enabled = True }) strings
    in
    Multi.multiSelect
        { onChange = UpdateMultiOptionValue optionName
        , items = items
        }
        []
        []


rmParam : List ( String, String ) -> String -> List ( String, String )
rmParam paramsList optToRemove =
    List.filter (\( k, v ) -> k /= optToRemove) paramsList


rmOptionValue : Dict String (List String) -> String -> Dict String (List String)
rmOptionValue optionValues optToRemove =
    let
        names =
            Set.fromList
                [ optToRemove
                , "min__" ++ optToRemove
                , "max__" ++ optToRemove
                ]
    in
    Dict.toList optionValues
        |> List.filter (\( k, v ) -> not (Set.member k names))
        |> Dict.fromList


mkRestrictedParams :
    Dict String String
    -> WebData (List SearchResult)
    -> Dict String String
mkRestrictedParams curParams searchResults =
    case searchResults of
        Success results ->
            let
                keys =
                    List.map (.attributes >> Dict.keys) results
                        |> List.concat
                        |> List.filter (\v -> v /= "_id")
                        |> List.Extra.unique

                types =
                    List.filterMap (\k -> Dict.get k curParams) keys
            in
            Dict.fromList (List.map2 (,) keys types)

        _ ->
            Dict.empty


mkResultRow : Int -> Cart.Model -> List ( String, String ) -> Dict String JsonType -> Html Msg
mkResultRow selectedRowId cart fieldList result =
    let
        mkTd : ( String, String ) -> Html msg
        mkTd ( fldName, dataType ) =
            let
                align =
--                    if dataType == "number" then
--                        "right"
--                    else
                        "left"
            in
            td [ style [ ( "text-align", align ) ] ] [ text (getVal fldName result) ]

        projectCol =
            let
                name =
                    getVal "specimen__project_name" result

                projectLink =
                    case String.toInt (getVal "specimen__project_id" result) of
                        Ok projectId ->
                            a [ Route.href (Route.Project projectId) ]
                                [ text name ]

                        Err _ ->
                            text name
            in
            td [ style [ ( "text-align", "left" ) ] ] [ projectLink ]

        sample_id =
            case String.toInt (getVal "specimen__sample_id" result) of
                Ok sampleId ->
                    sampleId

                Err _ ->
                    0

        nameCol =
            let
                name =
                    getVal "specimen__sample_name" result

                sampleLink =
                    case String.toInt (getVal "specimen__sample_id" result) of
                        Ok sampleId ->
                            a [ Route.href (Route.Sample sampleId) ]
                                [ text name ]

                        Err _ ->
                            text name
            in
            td [ style [ ( "text-align", "left" ) ] ] [ sampleLink ]

        typeCol =
            let
                name =
                    getVal "specimen__sample_type" result
            in
            td [ style [ ( "text-align", "left" ) ] ] [ text name ]

        cartCol =
            let
                sampleId =
                    case String.toInt (getVal "specimen__sample_id" result) of
                        Ok sampleId ->
                            sampleId

                        Err _ ->
                            0
            in
            td [ class "col-md-1" ] [ Cart.addToCartButton cart sampleId |> Html.map CartMsg ]

        otherCols =
            List.map mkTd fieldList

        isSelected =
            (sample_id == selectedRowId)
    in
    tr [ onDoubleClick (OpenInfoDialog sample_id), classList [("active", isSelected)] ] (projectCol :: nameCol :: typeCol :: otherCols ++ [cartCol])


getVal : String -> Dict String JsonType -> String
getVal fldName result =
    case Dict.get fldName result of
        Just (StrType s) ->
            s

        Just (IntType i) ->
            toString i

        Just (FloatType f) ->
            toString f

        Just (ValueType v) ->
            toString v

        _ ->
            "NA"


infoDialogConfig : Model -> Dialog.Config Msg
infoDialogConfig model =
    let
        content =
            case List.filter (\s -> s.sample_id == model.selectedRowId) model.samples of
                [] ->
                    text ""

                sample :: _ ->
                    div [ style [ ("margin-left","2em"), ("margin-right","2em") ] ]
                        [ View.Sample.viewInfo sample ]

        footer =
            button [ class "btn btn-default", onClick CloseInfoDialog ] [ text "Close" ]
    in
    { closeMessage = Just CloseInfoDialog
    , containerClass = Nothing
    , header = Just (h3 [] [ text "Sample Info" ])
    , body = Just content
    , footer = Just footer
    }
