module Page.Profile exposing (Model, Msg, init, update, view)

import Data.Profile as Profile exposing (Profile)
import Data.Session as Session exposing (Session)
import Html exposing (..)
import Html.Attributes exposing (..)
import Http
import Page.Error as Error exposing (PageLoadError, pageLoadError)
import Request.Agave
import Task exposing (Task)
import View.Page as Page


---- MODEL ----


type alias Model =
    { pageTitle : String
    , token : String
    , profile : Profile
    }


init : String -> Task PageLoadError Model
init token =
    let
        -- Load page - Perform tasks to load the resources of a page
        title =
            Task.succeed "Profile"

        loadProfile =
            Request.Agave.getProfile token |> Http.toTask |> Task.map .result

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
    Task.map3 Model title (Task.succeed token) loadProfile
        |> Task.mapError handleLoadError



-- UPDATE --


type Msg
    = Todo


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        Todo ->
            ( model, Cmd.none )



-- VIEW --


view : Model -> Html Msg
view model =
    let
        profile =
            model.profile
    in
    div [ class "container" ]
        [ h2 [] [ text model.pageTitle ]
        , table [ class "table" ]
            [ tr []
                [ th [] [ text "Username" ]
                , td [] [ text profile.username ]
                ]
            , tr []
                [ th [] [ text "Full name" ]
                , td [] [ text (profile.first_name ++ " " ++ profile.last_name) ]
                ]
            ]
        ]
