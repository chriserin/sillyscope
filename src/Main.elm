port module Main exposing (main)

import Browser
import Browser.Dom
import Browser.Events
import Dict exposing (Dict)
import Json.Decode as Json
import Json.Encode
import Model exposing (Action(..), Model, Note, ViewportAction(..), Waveform, WidthHeight, ZoomAction(..))
import OscilatorType exposing (OscilatorType(..))
import Task exposing (perform)
import View exposing (view)


port noteRelease : Json.Value -> Cmd msg


port notePress : Json.Value -> Cmd msg


port getWaveforms : Json.Value -> Cmd msg


port notePressed : (Json.Encode.Value -> msg) -> Sub msg


port waveforms : (Json.Encode.Value -> msg) -> Sub msg


init : () -> ( Model, Cmd Action )
init () =
    ( { notes = Dict.empty, waveforms = Dict.empty, audioSources = Dict.empty, zoom = 0.25, zoomStart = Nothing, scene = { width = 1, height = 1 }, oscilatorType = Sine }
    , perform (\viewport -> viewport |> ViewportSet |> Viewport) Browser.Dom.getViewport
    )


subscriptions : Model -> Sub Action
subscriptions model =
    Sub.batch
        [ Browser.Events.onResize (\w h -> WidthHeight w h |> ViewportChange |> Viewport)
        , waveforms UpdateWaveform
        , notePressed NotePressed
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
    [ ( "decay", Json.Encode.float 0.5 ), ( "node", node ) ] |> Json.Encode.object |> noteRelease


decodeNote : Json.Value -> Result Json.Error Note
decodeNote note =
    let
        decoder =
            Json.map2 Note (Json.field "id" Json.int) (Json.field "node" Json.value)
    in
    note |> Json.decodeValue decoder


type alias WaveformMessage =
    { id : Int, waveform : List Float }


decodeWaveforms forms model =
    let
        decoder =
            Json.map2 WaveformMessage (Json.field "id" Json.int) (Json.field "waveform" (Json.list Json.float))
                |> Json.list

        decodedWaveform =
            Json.decodeValue decoder forms

        updateWaveform wf note =
            Maybe.map (\n -> { n | data = wf }) note

        trim wf =
            wf |> Model.dropToLocalMinimum |> List.take (round model.scene.height)

        fold : List { id : Int, waveform : List Float } -> Dict Int Waveform -> Dict Int Waveform
        fold nextForms currentForms =
            currentForms
    in
    case decodedWaveform of
        Ok wfs ->
            { model | waveforms = List.foldl fold model.waveforms wfs }

        Err _ ->
            model


update : Action -> Model -> ( Model, Cmd Action )
update action model =
    case action of
        ToggleKey i ->
            case Dict.get i model.notes of
                Just note ->
                    case Dict.get i model.audioSources of
                        Just audioSource ->
                            ( { model | notes = Dict.remove i model.notes }, buildReleaseCommand audioSource )

                        Nothing ->
                            ( model, Cmd.none )

                Nothing ->
                    ( model, buildNoteCommand i model.oscilatorType )

        SetOscilatorType oscilatorType ->
            ( { model | oscilatorType = oscilatorType }, Cmd.none )

        UpdateWaveform forms ->
            ( decodeWaveforms forms model, buildGetWaveformsCommand model.notes )

        NotePressed note ->
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
            ( case viewPortAction of
                ViewportSet viewPort ->
                    { model | scene = viewPort.scene }

                ViewportChange viewPort ->
                    { model | scene = { width = toFloat viewPort.width, height = toFloat viewPort.height } }
            , Cmd.none
            )

        Zoom zoom ->
            ( case zoom of
                ZoomStart point ->
                    { model | zoomStart = Just point }

                ZoomChange point ->
                    case model.zoomStart of
                        Nothing ->
                            model

                        Just start ->
                            { model | zoom = (point.x - start.x) / model.scene.width }

                ZoomStop ->
                    { model | zoomStart = Nothing }
            , Cmd.none
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
