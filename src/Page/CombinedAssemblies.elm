module Page.CombinedAssemblies exposing (Model, Msg, init, update, view)

import Data.CombinedAssembly
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (onInput)
import Http
import List exposing (map)
import Page.Error as Error exposing (PageLoadError)
import Request.CombinedAssembly
import Route
import String exposing (join)
import Table exposing (defaultCustomizations)
import Task exposing (Task)
import View.Widgets



---- MODEL ----


type alias Model =
    { pageTitle : String
    , combinedAssemblies : List Data.CombinedAssembly.CombinedAssembly
    , tableState : Table.State
    , query : String
    }


init : Task PageLoadError Model
init =
    let
        -- Load page - Perform tasks to load the resources of a page
        title =
            Task.succeed "Combined Assemblies"

        loadCombinedAssemblies =
            Request.CombinedAssembly.list |> Http.toTask

        tblState =
            Task.succeed (Table.initialSort "Name")

        qry =
            Task.succeed ""
    in
    Task.map4 Model title loadCombinedAssemblies tblState qry
        |> Task.mapError Error.handleLoadError



-- UPDATE --


type Msg
    = SetQuery String
    | SetTableState Table.State


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        SetQuery newQuery ->
            ( { model | query = newQuery }
            , Cmd.none
            )

        SetTableState newState ->
            ( { model | tableState = newState }
            , Cmd.none
            )


config : Table.Config Data.CombinedAssembly.CombinedAssembly Msg
config =
    Table.customConfig
        { toId = .assembly_name
        , toMsg = SetTableState
        , columns =
            [ projectColumn
            , nameColumn
            , Table.stringColumn "Phylum" .phylum
            , Table.stringColumn "Class" .class
            , Table.stringColumn "Family" .family
            , Table.stringColumn "Genus" .genus
            , Table.stringColumn "Species" .species
            , Table.stringColumn "Strain" .strain
            , pcrColumn
            , annoColumn
            , cdsColumn
            , ntColumn
            , pepColumn
            ]
        , customizations =
            { defaultCustomizations | tableAttrs = toTableAttrs }
        }


toTableAttrs : List (Attribute Msg)
toTableAttrs =
    [ attribute "class" "table"
    ]


projectName : Data.CombinedAssembly.CombinedAssembly -> String
projectName assembly =
    case assembly.project of
        Nothing ->
            "NA"

        Just project ->
            project.project_name


projectColumn : Table.Column Data.CombinedAssembly.CombinedAssembly Msg
projectColumn =
    Table.veryCustomColumn
        { name = "Projects"
        , viewData = projectLink
        , sorter = Table.increasingOrDecreasingBy projectName
        }


projectLink : Data.CombinedAssembly.CombinedAssembly -> Table.HtmlDetails Msg
projectLink assembly =
    let
        link =
            case assembly.project of
                Nothing ->
                    text "NA"

                Just project ->
                    a [ Route.href (Route.Project project.project_id) ]
                        [ text project.project_name ]
    in
    Table.HtmlDetails [] [ link ]


nameColumn : Table.Column Data.CombinedAssembly.CombinedAssembly Msg
nameColumn =
    Table.veryCustomColumn
        { name = "Name"
        , viewData = nameLink
        , sorter = Table.unsortable
        }


nameLink : Data.CombinedAssembly.CombinedAssembly -> Table.HtmlDetails Msg
nameLink assembly =
    Table.HtmlDetails []
        [ a [ Route.href (Route.CombinedAssembly assembly.combined_assembly_id) ]
            [ text assembly.assembly_name ]
        ]


annoText : Data.CombinedAssembly.CombinedAssembly -> String
annoText assembly =
    case assembly.anno_file of
        "" -> "No"

        _ -> "Yes"


annoColumn : Table.Column Data.CombinedAssembly.CombinedAssembly Msg
annoColumn =
    Table.veryCustomColumn
        { name = "Anno"
        , viewData = annoLink
        , sorter = Table.increasingOrDecreasingBy annoText
        }


annoLink : Data.CombinedAssembly.CombinedAssembly -> Table.HtmlDetails Msg
annoLink assembly =
    Table.HtmlDetails [ style [("min-width","4em")] ] -- min-width is to prevent column header from wrapping
        [ text (annoText assembly) ]


pcrText : Data.CombinedAssembly.CombinedAssembly -> String
pcrText assembly =
    case assembly.pcr_amp of
        "" -> "No"

        _ -> "Yes"


pcrColumn : Table.Column Data.CombinedAssembly.CombinedAssembly Msg
pcrColumn =
    Table.veryCustomColumn
        { name = "PCR Amp"
        , viewData = pcrLink
        , sorter = Table.increasingOrDecreasingBy pcrText
        }


pcrLink : Data.CombinedAssembly.CombinedAssembly -> Table.HtmlDetails Msg
pcrLink assembly =
    Table.HtmlDetails [ style [("min-width","4em")] ] -- min-width is to prevent column header from wrapping
        [ text (pcrText assembly) ]


cdsText : Data.CombinedAssembly.CombinedAssembly -> String
cdsText assembly =
    case assembly.anno_file of
        "" -> "No"

        _ -> "Yes"


cdsColumn : Table.Column Data.CombinedAssembly.CombinedAssembly Msg
cdsColumn =
    Table.veryCustomColumn
        { name = "CDS"
        , viewData = cdsLink
        , sorter = Table.increasingOrDecreasingBy cdsText
        }


cdsLink : Data.CombinedAssembly.CombinedAssembly -> Table.HtmlDetails Msg
cdsLink assembly =
    Table.HtmlDetails [ style [("min-width","4em")] ] -- min-width is to prevent column header from wrapping
        [ text (cdsText assembly) ]


ntText : Data.CombinedAssembly.CombinedAssembly -> String
ntText assembly =
    case assembly.nt_file of
        "" -> "No"

        _ -> "Yes"


ntColumn : Table.Column Data.CombinedAssembly.CombinedAssembly Msg
ntColumn =
    Table.veryCustomColumn
        { name = "NT"
        , viewData = ntLink
        , sorter = Table.increasingOrDecreasingBy ntText
        }


ntLink : Data.CombinedAssembly.CombinedAssembly -> Table.HtmlDetails Msg
ntLink assembly =
    Table.HtmlDetails []
        [ text (ntText assembly) ]


pepText : Data.CombinedAssembly.CombinedAssembly -> String
pepText assembly =
    case assembly.pep_file of
        "" -> "No"

        _ -> "Yes"


pepColumn : Table.Column Data.CombinedAssembly.CombinedAssembly Msg
pepColumn =
    Table.veryCustomColumn
        { name = "PEP"
        , viewData = pepLink
        , sorter = Table.increasingOrDecreasingBy pepText
        }


pepLink : Data.CombinedAssembly.CombinedAssembly -> Table.HtmlDetails Msg
pepLink assembly =
    Table.HtmlDetails []
        [ text (pepText assembly) ]



-- VIEW --


view : Model -> Html Msg
view model =
    let
        lowerQuery =
            String.toLower model.query

        acceptableAssemblies =
            List.filter (String.contains lowerQuery << String.toLower << .assembly_name) model.combinedAssemblies
    in
    div [ class "container" ]
        [ div [ class "row" ]
            [ h1 []
                [ text (model.pageTitle ++ " ")
                , View.Widgets.counter (List.length acceptableAssemblies)
                , small [ class "right" ]
                    [ input [ placeholder "Search by Name", onInput SetQuery ] [] ]
                ]
            , Table.view config model.tableState acceptableAssemblies
            ]
        ]
