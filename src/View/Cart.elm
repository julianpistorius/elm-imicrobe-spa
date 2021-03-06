module View.Cart exposing (Model, Msg(..), init, update, viewCart, addToCartButton, addToCartButton2, addAllToCartButton, size, CartType(..))

import Data.Session as Session exposing (Session)
import Data.Cart as Cart exposing (Cart)
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (onClick)
import Table exposing (defaultCustomizations)
import Route
import Util exposing ((=>))
import Set



type CartType
    = Selectable
    | Editable


type alias Model =
    { cart : Cart
    , tableState : Table.State
    , cartType : CartType
    , selected : Cart
    }


init : Cart -> CartType -> Model
init cart cartType =
    Model cart (Table.initialSort "Name") cartType Cart.empty



-- UPDATE --


type Msg
    = AddToCart Int
    | RemoveFromCart Int
    | AddAllToCart (List Int)
    | RemoveAllFromCart (List Int)
    | ToggleSelectInCart Int
    | SelectAllInCart
    | UnselectAllInCart
    | SetTableState Table.State
    | SetSession Session


type ExternalMsg
    = NoOp
    | SetCart Cart


update : Session -> Msg -> Model -> ( ( Model, Cmd Msg ), ExternalMsg )
update session msg model =
    case msg of
        AddToCart id ->
            let
                newCart =
                    Cart.add model.cart id

                newSession =
                    { session | cart = newCart }
            in
            { model | cart = newCart } => Session.store newSession => SetCart newCart

        RemoveFromCart id ->
            let
                newCart =
                    Cart.remove model.cart id

                newSession =
                    { session | cart = newCart }
            in
            { model | cart = newCart } => Session.store newSession => SetCart newCart

        AddAllToCart ids ->
            let
                newCart =
                    Cart.addList model.cart ids

                newSession =
                    { session | cart = newCart }
            in
            { model | cart = newCart } => Session.store newSession => SetCart newCart

        RemoveAllFromCart ids ->
            let
                newCart =
                    Cart.removeList model.cart ids

                newSession =
                    { session | cart = newCart }
            in
            { model | cart = newCart } => Session.store newSession => SetCart newCart

        ToggleSelectInCart id ->
            let
                selected =
                    if Cart.contains model.selected id then
                        Cart.remove model.selected id
                    else
                        Cart.add model.selected id
            in
            { model | selected = selected } => Cmd.none => NoOp

        SelectAllInCart ->
            let
                selected =
                    Cart.addList model.selected (Set.toList model.cart.contents)
            in
            { model | selected = selected } => Cmd.none => NoOp

        UnselectAllInCart ->
            let
                selected = Cart.empty
            in
            { model | selected = selected } => Cmd.none => NoOp

        SetTableState newState ->
            { model | tableState = newState } => Cmd.none => NoOp

        SetSession newSession ->
            let
                newCart =
                    newSession.cart
            in
            { model | cart = newCart } => Cmd.none => NoOp



-- VIEW --


config : Model -> Table.Config { a | sample_id : Int, sample_name : String, project : { b | project_id : Int, project_name : String } } Msg
config model =
    let
        columns =
            case model.cartType of
                Editable ->
                    [ projectColumn
                    , nameColumn
                    , removeFromCartColumn
                    ]

                Selectable ->
                    [ selectInCartColumn model
                    , projectColumn
                    , nameColumn
                    ]
    in
    Table.customConfig
        { toId = toString << .sample_id
        , toMsg = SetTableState
        , columns = columns
        , customizations =
            { defaultCustomizations | tableAttrs = toTableAttrs }
        }


toTableAttrs : List (Attribute Msg)
toTableAttrs =
    [ attribute "class" "table"
    ]


viewCart : Model -> List { a | sample_id : Int, sample_name : String, project : { b | project_id : Int, project_name : String } } -> Html Msg
viewCart model samples =
    Table.view (config model) model.tableState (samplesInCart model.cart samples)


selectInCartColumn : Model -> Table.Column { a | sample_id : Int, sample_name : String } Msg
selectInCartColumn model =
    Table.veryCustomColumn
        { name = ""
        , viewData = (\s -> selectInCartLink model s)
        , sorter = Table.unsortable
        }


selectInCartLink : Model -> { a | sample_id : Int, sample_name : String } -> Table.HtmlDetails Msg
selectInCartLink model sample =
    let
        isChecked =
            Set.member sample.sample_id model.selected.contents
    in
    Table.HtmlDetails []
        [ selectInCartCheckbox sample.sample_id isChecked -- |> Html.map (\_ -> ToggleSelectInCart sample.sample_id)
        ]


selectInCartCheckbox : Int -> Bool -> Html Msg
selectInCartCheckbox id isChecked =
    input [ type_ "checkbox", checked isChecked, onClick (ToggleSelectInCart id) ] []


projectColumn : Table.Column { a | sample_id : Int, sample_name : String, project : { b | project_id : Int, project_name : String } } Msg
projectColumn =
    Table.veryCustomColumn
        { name = "Project"
        , viewData = projectLink
        , sorter = Table.increasingOrDecreasingBy (.project >> .project_name >> String.toLower)
        }


projectLink : { a | sample_id : Int, sample_name : String, project : { b | project_id : Int, project_name : String } } -> Table.HtmlDetails Msg
projectLink sample =
    Table.HtmlDetails []
        [ a [ Route.href (Route.Project sample.project.project_id) ]
            [ text <| Util.truncate sample.project.project_name ]
        ]


nameColumn : Table.Column { a | sample_id : Int, sample_name : String } Msg
nameColumn =
    Table.veryCustomColumn
        { name = "Sample"
        , viewData = nameLink
        , sorter = Table.increasingOrDecreasingBy (String.toLower << .sample_name)
        }


nameLink : { a | sample_id : Int, sample_name : String } -> Table.HtmlDetails Msg
nameLink sample =
    Table.HtmlDetails []
        [ a [ Route.href (Route.Sample sample.sample_id) ]
            [ text <| Util.truncate sample.sample_name ]
        ]


removeFromCartColumn : Table.Column { a | sample_id : Int, sample_name : String } Msg
removeFromCartColumn =
    Table.veryCustomColumn
        { name = ""
        , viewData = removeFromCartLink
        , sorter = Table.unsortable
        }


removeFromCartLink : { a | sample_id : Int, sample_name : String } -> Table.HtmlDetails Msg
removeFromCartLink sample =
    Table.HtmlDetails []
        [ removeFromCartButton sample.sample_id |> Html.map (\_ -> RemoveFromCart sample.sample_id)
        ]


removeFromCartButton : Int -> Html Msg
removeFromCartButton id =
    button [ class "btn btn-default btn-xs", onClick (RemoveFromCart id) ] [ text "Remove" ]


addToCartButton : Model -> Int -> Html Msg
addToCartButton model id =
    if Set.member id model.cart.contents then
        button [ class "btn btn-default btn-xs", onClick (RemoveFromCart id) ] [ text "Remove" ]
    else
        button [ class "btn btn-default btn-xs", onClick (AddToCart id) ] [ text "Add" ]


-- Kludge
addToCartButton2 : Model -> Int -> Html Msg
addToCartButton2 model id =
    let
        icon =
            span [ class "glyphicon glyphicon-shopping-cart" ] []
    in
    if Set.member id model.cart.contents then
        button [ class "btn btn-default", onClick (RemoveFromCart id) ] [ icon, text " Remove from Cart" ]
    else
        button [ class "btn btn-default", onClick (AddToCart id) ] [ icon, text " Add to Cart" ]


addAllToCartButton : Model -> Maybe (String, String) -> List Int -> Html Msg
addAllToCartButton model optionalLabels ids =
    let
        (addLbl, removeLbl) =
            case optionalLabels of
                Just labels ->
                    labels

                Nothing ->
                    ( "Add All", "Remove All" )

        intersection =
            Set.intersect (Set.fromList ids) model.cart.contents |> Set.toList
    in
    if intersection == [] then
        button [ class "btn btn-default btn-xs", onClick (AddAllToCart ids) ] [ text addLbl ]
    else
        button [ class "btn btn-default btn-xs", onClick (RemoveAllFromCart ids) ] [ text removeLbl ]


samplesInCart : Cart -> List { a | sample_id : Int, sample_name : String } -> List { a | sample_id : Int, sample_name : String }
samplesInCart cart samples =
    List.filter (\sample -> Set.member sample.sample_id cart.contents) samples


size : Model -> Int
size model =
    Set.size model.cart.contents