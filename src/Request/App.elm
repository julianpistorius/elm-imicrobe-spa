module Request.App exposing (..)

import Data.App as App exposing (App, AppRun, decoderAppRun, encodeAppRun)
import Http
import HttpBuilder exposing (RequestBuilder, withExpect, withQueryParams)
import Json.Decode as Decode exposing (Decoder, string)
import Config exposing (apiBaseUrl)



list : Http.Request (List App)
list =
    let
        url =
            apiBaseUrl ++ "/apps"

        decoder =
            Decode.list App.decoder
    in
    HttpBuilder.get url
        |> HttpBuilder.withExpect (Http.expectJson decoder)
        |> HttpBuilder.toRequest


get : Int -> Http.Request App
get id =
    HttpBuilder.get (apiBaseUrl ++ "/apps/" ++ toString id)
        |> HttpBuilder.withExpect (Http.expectJson App.decoder)
        |> HttpBuilder.toRequest


getByName : String -> Http.Request App
getByName name =
    HttpBuilder.get (apiBaseUrl ++ "/apps/" ++ name)
        |> HttpBuilder.withExpect (Http.expectJson App.decoder)
        |> HttpBuilder.toRequest


run : String -> Int -> String -> Http.Request AppRun
run token app_id params =
    let
        url =
            apiBaseUrl ++ "/apps/runs"

        headers =
            [( "Authorization", token)]
    in
    HttpBuilder.post url
        |> HttpBuilder.withHeaders headers
        |> HttpBuilder.withJsonBody (encodeAppRun app_id params)
        |> HttpBuilder.withExpect (Http.expectJson decoderAppRun)
        |> HttpBuilder.toRequest