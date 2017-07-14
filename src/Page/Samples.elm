module Page.Samples exposing (Model, Msg, init, update, view)

import Data.Sample
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (onInput)
import Http
import Page.Error as Error exposing (PageLoadError, pageLoadError)
import Request.Sample
import Route
import Table
import Task exposing (Task)
import View.Page as Page
import String exposing (join)
import List exposing (map)


---- MODEL ----


type alias Model =
    { pageTitle : String
    , samples : List Data.Sample.Sample
    , tableState : Table.State
    , query : String
    }


init : Task PageLoadError Model
init =
    let
        -- Load page - Perform tasks to load the resources of a page
        title =
            Task.succeed "Samples"

        loadSamples =
            Request.Sample.list |> Http.toTask

        tblState =
            Task.succeed (Table.initialSort "Name")

        qry =
            Task.succeed ""

        handleLoadError err =
            -- If a resource task fail load error page
            let
                errMsg =
                    case err of
                        Http.BadStatus response ->
                            case String.length response.body of
                                0 ->
                                    "Bad status"

                                _ ->
                                    response.body

                        _ ->
                            toString err
            in
            Error.pageLoadError Page.Home errMsg
    in
    Task.map4 Model title loadSamples tblState qry
        |> Task.mapError handleLoadError



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


config : Table.Config Data.Sample.Sample Msg
config =
    Table.config
        { toId = toString << .sample_id
        , toMsg = SetTableState
        , columns =
            [ Table.stringColumn "Project" .project_name
            , Table.stringColumn "Sample" .sample_name
            , Table.stringColumn "Type" .sample_type
            ]
        }



-- VIEW --


view : Model -> Html Msg
view model =
    let
        query =
            model.query

        lowerQuery =
            String.toLower query

        acceptableSamples =
            List.filter (String.contains lowerQuery << String.toLower << .sample_name) model.samples
    in
    div [ class "container" ]
        [ div [ class "row" ]
            [ h2 [] [ text model.pageTitle ]
            , input [ placeholder "Search by Name", onInput SetQuery ] []
            , Table.view config model.tableState acceptableSamples
            ]
        ]


viewSamples samples =
    case List.length samples of
        0 ->
            text "No samples"

        _ ->
            table [ class "table" ]
                [ thead []
                    [ tr []
                        [ th [] [ text "Name" ]
                        ]
                    ]
                , tbody []
                    (List.map rowSample samples)
                ]


rowSample sample =
    tr []
        [ td []
            [ a [ Route.href (Route.Sample sample.sample_id) ]
                [ text sample.sample_name ]
            ]
        ]