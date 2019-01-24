port module Main exposing (main)

import Browser
import Browser.Dom
import Browser.Events
import Dict exposing (Dict)
import Json.Decode as Json
import Json.Encode
import Model exposing (Action(..), AudioSource, Model, ViewportAction(..), Waveform, WidthHeight, ZoomAction(..), micId)
import OscilatorType exposing (OscilatorType(..))
import Task exposing (attempt, perform)
import View exposing (view)


port releaseAudioSource : Json.Value -> Cmd msg


port notePress : Json.Value -> Cmd msg


port getWaveforms : Json.Value -> Cmd msg


port activateMic : Json.Value -> Cmd msg


port addAudioSource : (Json.Encode.Value -> msg) -> Sub msg


port waveforms : (Json.Encode.Value -> msg) -> Sub msg


init : () -> ( Model, Cmd Action )
init () =
    ( { waveforms = Dict.empty, audioSources = Dict.empty, zoom = 1, zoomStart = Nothing, wrapperElement = Nothing, oscilatorType = Sine }
    , perform (\viewport -> viewport |> ViewportSet |> Viewport) Browser.Dom.getViewport
    )


subscriptions : Model -> Sub Action
subscriptions model =
    Sub.batch
        [ Browser.Events.onResize (\w h -> WidthHeight w h |> ViewportChange |> Viewport)
        , waveforms UpdateWaveform
        , addAudioSource AddAudioSource
        ]


main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }


buildNoteCommand n ot =
    let
        -- middle c
        freq =
            (n + 3) |> interval |> (*) 220

        oscilatorType =
            OscilatorType.toString ot

        json =
            Json.Encode.object
                [ ( "id", Json.Encode.int n )
                , ( "frequency", Json.Encode.float freq )
                , ( "attack", Json.Encode.float 0.1 )
                , ( "type", Json.Encode.string oscilatorType )
                ]
    in
    json |> notePress


buildReleaseCommand { node } =
    [ ( "release", Json.Encode.float 0.5 ), ( "node", node ) ] |> Json.Encode.object |> releaseAudioSource


decodeNote : Json.Value -> Result Json.Error AudioSource
decodeNote note =
    let
        decoder =
            Json.map2 AudioSource (Json.field "id" Json.int) (Json.field "node" Json.value)
    in
    note |> Json.decodeValue decoder


type alias WaveformMessage =
    { id : Int, data : Waveform }


decodeWaveforms forms model =
    let
        decoder =
            Json.map2 WaveformMessage (Json.field "id" Json.int) (Json.field "data" (Json.list Json.float))
                |> Json.list

        decodedWaveform =
            Json.decodeValue decoder forms

        updateNote wf note =
            Maybe.map (\n -> { n | waveform = wf }) note

        frameCount =
            case model.wrapperElement of
                Nothing ->
                    0

                Just element ->
                    round (element.element.width * model.zoom)

        trim wf =
            wf |> Model.dropToLocalMinimum |> List.take frameCount

        fold : WaveformMessage -> Dict Int Waveform -> Dict Int Waveform
        fold { id, data } currentForms =
            case Dict.get id model.audioSources of
                Just _ ->
                    Dict.insert id (trim data) currentForms

                Nothing ->
                    Dict.remove id currentForms
    in
    case Json.decodeValue decoder forms of
        Ok wfs ->
            { model | waveforms = List.foldl fold model.waveforms wfs }

        Err _ ->
            model


update : Action -> Model -> ( Model, Cmd Action )
update action model =
    case action of
        ToggleKey i ->
            toggleAudioSource i model |> Maybe.withDefault ( model, buildNoteCommand i model.oscilatorType )

        SetOscilatorType oscilatorType ->
            ( { model | oscilatorType = oscilatorType }, Cmd.none )

        UpdateWaveform forms ->
            ( decodeWaveforms forms model, buildGetWaveformsCommand model.audioSources )

        AddAudioSource note ->
            case decodeNote note of
                Ok o ->
                    let
                        audioSources =
                            Dict.insert o.id o model.audioSources
                    in
                    ( { model | audioSources = audioSources }, buildGetWaveformsCommand audioSources )

                Err _ ->
                    ( model, Cmd.none )

        Viewport viewPortAction ->
            let
                getWrapper =
                    "scope-wrapper" |> Browser.Dom.getElement |> attempt (\result -> Viewport (WrapperElement result))
            in
            case viewPortAction of
                WrapperElement result ->
                    ( { model | wrapperElement = Result.toMaybe result }, Cmd.none )

                ViewportSet viewPort ->
                    ( model, getWrapper )

                ViewportChange viewPort ->
                    ( model, getWrapper )

        Zoom zoom ->
            ( case zoom of
                ZoomStart point ->
                    { model | zoomStart = Just point }

                ZoomChange point ->
                    case model.zoomStart of
                        Nothing ->
                            model

                        Just start ->
                            case model.wrapperElement of
                                Nothing ->
                                    model

                                Just element ->
                                    { model | zoom = (point.x - start.x) / element.element.width }

                ZoomStop ->
                    { model | zoomStart = Nothing }
            , Cmd.none
            )

        ToggleMic ->
            toggleAudioSource micId model
                |> Maybe.withDefault ( model, [ ( "id", Json.Encode.int micId ) ] |> Json.Encode.object |> activateMic )


toggleAudioSource : Int -> Model -> Maybe ( Model, Cmd a )
toggleAudioSource id model =
    model.audioSources
        |> Dict.get id
        |> Maybe.map
            (\audioSource ->
                ( { model
                    | audioSources = Dict.remove id model.audioSources
                  }
                , buildReleaseCommand audioSource
                )
            )


buildGetWaveformsCommand notes =
    case Dict.values notes of
        [] ->
            Cmd.none

        values ->
            values
                |> Json.Encode.list
                    (\note ->
                        Json.Encode.object [ ( "id", Json.Encode.int note.id ), ( "node", note.node ) ]
                    )
                |> getWaveforms


interval : Int -> Float
interval n =
    2 ^ (toFloat n / 12.0)
