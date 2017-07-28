port module Main exposing (..)

import Html exposing (..)
import Navigation exposing (Location)
import Page.About as About
import Page.Error as Error exposing (PageLoadError)
import Page.Home as Home
import Page.Investigator as Investigator
import Page.Investigators as Investigators
import Page.NotFound as NotFound
import Page.Project as Project
import Page.Projects as Projects
import Page.Sample as Sample
import Page.Samples as Samples
import Page.Profile as Profile
import Page.Search as Search
import Page.Map as Map
import Route exposing (..)
import Task
import Util exposing ((=>))
import View.Page as Page exposing (ActivePage)
import OAuth
import OAuth.Implicit
import Debug exposing (log)


---- MODEL ----


type alias Model =
    { pageState : PageState
    , oauth :
          { authEndpoint : String
          , clientId : String
          , redirectUri : String
          }
    , token : Maybe OAuth.Token
    , error : Maybe String
    }


type Page
    = Blank
    | NotFound
    | Error PageLoadError
    | Home Home.Model
    | About About.Model
    | Profile String Profile.Model
    | Investigator Int Investigator.Model
    | Investigators Investigators.Model
    | Project Int Project.Model
    | Projects Projects.Model
    | Samples Samples.Model
    | Sample Int Sample.Model
    | Search Search.Model
    | Map String String Map.Model


type PageState
    = Loaded Page
    | TransitioningFrom Page



---- UPDATE ----


type Msg
    = SetRoute (Maybe Route)
    | AboutLoaded (Result PageLoadError About.Model)
    | AboutMsg About.Msg
    | HomeLoaded (Result PageLoadError Home.Model)
    | HomeMsg Home.Msg
    | InvestigatorLoaded Int (Result PageLoadError Investigator.Model)
    | InvestigatorMsg Investigator.Msg
    | InvestigatorsLoaded (Result PageLoadError Investigators.Model)
    | InvestigatorsMsg Investigators.Msg
    | ProjectLoaded Int (Result PageLoadError Project.Model)
    | ProjectMsg Project.Msg
    | ProjectsLoaded (Result PageLoadError Projects.Model)
    | ProjectsMsg Projects.Msg
    | SampleLoaded Int (Result PageLoadError Sample.Model)
    | SampleMsg Sample.Msg
    | SamplesLoaded (Result PageLoadError Samples.Model)
    | SamplesMsg Samples.Msg
    | Authorize (Result PageLoadError Home.Model)
    | ProfileLoaded String (Result PageLoadError Profile.Model)
    | ProfileMsg Profile.Msg
    | SearchLoaded (Result PageLoadError Search.Model)
    | SearchMsg Search.Msg
    | MapLoaded String String (Result PageLoadError Map.Model)
    | MapMsg Map.Msg


setRoute : Maybe Route -> Model -> ( Model, Cmd Msg )
setRoute maybeRoute model =
    let
        transition toMsg task =
            { model | pageState = TransitioningFrom (getPage model.pageState) }
                => Task.attempt toMsg task

        error =
            pageError model
    in
    case maybeRoute of
        Nothing ->
            { model | pageState = Loaded NotFound } => Cmd.none

        Just Route.Home ->
            transition HomeLoaded Home.init

        Just Route.About ->
            transition AboutLoaded About.init

        Just Route.Login ->
            transition Authorize Home.init

        Just (Route.Investigator id) ->
            transition (InvestigatorLoaded id) (Investigator.init id)

        Just Route.Investigators ->
            transition InvestigatorsLoaded Investigators.init

        Just Route.Projects ->
            transition ProjectsLoaded Projects.init

        Just (Route.Project id) ->
            transition (ProjectLoaded id) (Project.init id)

        Just Route.Samples ->
            transition SamplesLoaded Samples.init

        Just (Route.Sample id) ->
            transition (SampleLoaded id) (Sample.init id)

        Just Route.Search ->
            transition SearchLoaded Search.init

        Just (Route.Profile token) ->
            transition (ProfileLoaded token) (Profile.init token)

        Just (Route.Map lat lng) ->
            transition (MapLoaded lat lng) (Map.init lat lng)


getPage : PageState -> Page
getPage pageState =
    case pageState of
        Loaded page ->
            page

        TransitioningFrom page ->
            page


pageError : Model -> ActivePage -> String -> ( Model, Cmd msg )
pageError model activePage errorMessage =
    let
        error =
            Error.pageLoadError activePage errorMessage
    in
    { model | pageState = Loaded (Error error) } => Cmd.none


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    updatePage (getPage model.pageState) msg model


updatePage : Page -> Msg -> Model -> ( Model, Cmd Msg )
updatePage page msg model =
    let
        toPage toModel toMsg subUpdate subMsg subModel =
            let
                ( newModel, newCmd ) =
                    subUpdate subMsg subModel
            in
            ( { model | pageState = Loaded (toModel newModel) }, Cmd.map toMsg newCmd )

        error =
            pageError model
    in
    case ( msg, page ) of
        ( SetRoute route, _ ) ->
            setRoute route model

        ( Authorize (Ok subModel), _) ->
            model
                ! [ OAuth.Implicit.authorize
                        { clientId = model.oauth.clientId
                        , redirectUri = model.oauth.redirectUri
                        , responseType = OAuth.Token
                        , scope = [ "PRODUCTION" ]
                        , state = Just "000"
                        , url = model.oauth.authEndpoint
                        }
                  ]

        ( ProfileLoaded token (Ok subModel), _ ) ->
            { model | pageState = Loaded (Profile token subModel) } => Cmd.none

        ( ProfileLoaded token (Err error), _ ) ->
            { model | pageState = Loaded (Error error) } => Cmd.none

        ( AboutLoaded (Ok subModel), _ ) ->
            { model | pageState = Loaded (About subModel) } => Cmd.none

        ( AboutLoaded (Err error), _ ) ->
            { model | pageState = Loaded (Error error) } => Cmd.none

        ( HomeLoaded (Ok subModel), _ ) ->
            { model | pageState = Loaded (Home subModel) } => Cmd.none

        ( HomeLoaded (Err error), _ ) ->
            { model | pageState = Loaded (Error error) } => Cmd.none

        ( InvestigatorLoaded id (Ok subModel), _ ) ->
            { model | pageState = Loaded (Investigator id subModel) } => Cmd.none

        ( InvestigatorLoaded id (Err error), _ ) ->
            { model | pageState = Loaded (Error error) } => Cmd.none

        ( InvestigatorsLoaded (Ok subModel), _ ) ->
            { model | pageState = Loaded (Investigators subModel) } => Cmd.none

        ( InvestigatorsLoaded (Err error), _ ) ->
            { model | pageState = Loaded (Error error) } => Cmd.none

        ( InvestigatorsMsg subMsg, Investigators subModel ) ->
            (toPage Investigators InvestigatorsMsg Investigators.update subMsg subModel)

        ( ProjectsLoaded (Ok subModel), _ ) ->
            { model | pageState = Loaded (Projects subModel) } => Cmd.none

        ( ProjectsLoaded (Err error), _ ) ->
            { model | pageState = Loaded (Error error) } => Cmd.none

        ( ProjectsMsg subMsg, Projects subModel ) ->
            toPage Projects ProjectsMsg Projects.update subMsg subModel

        ( ProjectLoaded id (Ok subModel), _ ) ->
            { model | pageState = Loaded (Project id subModel) } => Cmd.none

        ( ProjectLoaded id (Err error), _ ) ->
            { model | pageState = Loaded (Error error) } => Cmd.none

        ( SampleLoaded id (Ok subModel), _ ) ->
            { model | pageState = Loaded (Sample id subModel) } => Cmd.none

        ( SampleLoaded id (Err error), _ ) ->
            { model | pageState = Loaded (Error error) } => Cmd.none

        ( SamplesLoaded (Ok subModel), _ ) ->
            { model | pageState = Loaded (Samples subModel) } => Cmd.none

        ( SamplesLoaded (Err error), _ ) ->
            { model | pageState = Loaded (Error error) } => Cmd.none

        ( SamplesMsg subMsg, Samples subModel ) ->
            toPage Samples SamplesMsg Samples.update subMsg subModel

        ( SearchLoaded (Ok subModel), _ ) ->
            { model | pageState = Loaded (Search subModel) } => Cmd.none

        ( SearchLoaded (Err error), _ ) ->
            { model | pageState = Loaded (Error error) } => Cmd.none

        ( SearchMsg subMsg, Search subModel ) ->
            toPage Search SearchMsg Search.update subMsg subModel

        ( HomeMsg subMsg, Home subModel ) ->
            toPage Home HomeMsg Home.update subMsg subModel

        ( AboutMsg subMsg, About subModel ) ->
            toPage About AboutMsg About.update subMsg subModel

        ( MapLoaded lat lng (Ok subModel), _ ) ->
            { model | pageState = Loaded (Map lat lng subModel) } => Cmd.none

        ( MapLoaded lat lng (Err error), _ ) ->
            { model | pageState = Loaded (Error error) } => Cmd.none

        ( MapMsg subMsg, Map lat lng subModel ) ->
            toPage (Map lat lng) MapMsg Map.update subMsg subModel

        ( _, NotFound ) ->
            -- Disregard incoming messages when we're on the
            -- NotFound page.
            model => Cmd.none

        ( _, _ ) ->
            -- Disregard incoming messages that arrived for the wrong page
            model => Cmd.none



---- VIEW ----


view : Model -> Html Msg
view model =
    case model.pageState of
        Loaded page ->
            viewPage False page

        TransitioningFrom page ->
            viewPage True page


viewPage : Bool -> Page -> Html Msg
viewPage isLoading page =
    let
        layout =
            Page.layout isLoading
    in
    case page of
        NotFound ->
            layout Page.Other NotFound.view

        Blank ->
            -- This is for the very intial page load, while we are loading
            -- data via HTTP. We could also render a spinner here.
            Html.text ""
                |> layout Page.Other

        Error subModel ->
            Error.view subModel
                |> layout Page.Other

        Home subModel ->
            Home.view subModel
                |> layout Page.Home
                |> Html.map HomeMsg

        About subModel ->
            About.view subModel
                |> layout Page.About
                |> Html.map AboutMsg

        Profile token subModel ->
            Profile.view subModel
                |> layout Page.Profile
                |> Html.map ProfileMsg

        Investigator id subModel ->
            Investigator.view subModel
                |> layout Page.Investigator
                |> Html.map InvestigatorMsg

        Investigators subModel ->
            Investigators.view subModel
                |> layout Page.Investigators
                |> Html.map InvestigatorsMsg

        Projects subModel ->
            Projects.view subModel
                |> layout Page.Projects
                |> Html.map ProjectsMsg

        Samples subModel ->
            Samples.view subModel
                |> layout Page.Samples
                |> Html.map SamplesMsg

        Sample id subModel ->
            Sample.view subModel
                |> layout Page.Sample
                |> Html.map SampleMsg

        Project id subModel ->
            Project.view subModel
                |> layout Page.Project
                |> Html.map ProjectMsg

        Search subModel ->
            Search.view subModel
                |> layout Page.Search
                |> Html.map SearchMsg

        Map lat lng subModel ->
            Map.view subModel
                |> layout Page.Map
                |> Html.map MapMsg



---- SUBSCRIPTIONS ----


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.none



---- PORTS ----


port saveAuthToken : String -> Cmd msg


--port getAuthToken : (String -> msg) -> Sub msg



---- PROGRAM ----


initialPage : Page
initialPage =
    Blank


type alias Flags =
    { oauthClientId : String
    }


init : Flags -> Location -> ( Model, Cmd Msg )
init flags location =
    let
        model =
            { oauth =
                { authEndpoint = "https://agave.iplantc.org/authorize"
                , clientId = flags.oauthClientId
                , redirectUri = "http://localhost:8080/" --location.origin ++ location.pathname
                }
            , error = Nothing
            , token = Nothing
            , pageState = Loaded initialPage
            }

        _ = Debug.log "flags " flags

        -- Kludge for Agave not returning required "token_type=bearer" in redirect
        location2 = { location | hash = (location.hash ++ "&token_type=bearer") }
    in
        case OAuth.Implicit.parse location2 of
            Ok { token } ->
                let
                    saveToken = saveAuthToken (toString token)
                in
                    Tuple.mapSecond (\c -> Cmd.batch [ c, saveToken ])
                        (setRoute (Just (Route.Profile (toString token))) { model | token = Just token })

            Err OAuth.Empty ->
                let _ = Debug.log "OAuth.Empty" ""
                in
                    setRoute (Route.fromLocation location) model

            Err (OAuth.OAuthErr err) ->
                let _ = Debug.log "OAuth.OAuthErr" err
                in
                    { model | error = Just <| OAuth.showErrCode err.error }
                        ! [ Navigation.modifyUrl model.oauth.redirectUri ]

            Err a ->
                let _ = Debug.log "Error" ((toString a) ++ (toString location2))
                in
                    { model | error = Just "parsing error" } ! []


main : Program Flags Model Msg
main =
    Navigation.programWithFlags (Route.fromLocation >> SetRoute)
        { init = init
        , view = view
        , update = update
        , subscriptions = subscriptions
        }
