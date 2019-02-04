module Ports exposing (decodeAudioSource, encodeGetFftsCommand, encodeGetWaveformsCommand, encodeNoteCommand, encodeReleaseCommand)

import Dict exposing (Dict)
import Json.Decode
import Json.Encode
import Model exposing (AudioSource)
import OscilatorType exposing (OscilatorType)


encodeNoteCommand : Int -> Float -> OscilatorType -> Json.Encode.Value
encodeNoteCommand id freq ot =
    let
        oscilatorType =
            OscilatorType.toString ot
    in
    Json.Encode.object
        [ ( "id", Json.Encode.int id )
        , ( "frequency", Json.Encode.float freq )
        , ( "attack", Json.Encode.float 0.1 )
        , ( "type", Json.Encode.string oscilatorType )
        ]


encodeReleaseCommand { node } =
    [ ( "release", Json.Encode.float 0.5 ), ( "node", node ) ] |> Json.Encode.object


decodeAudioSource : Json.Decode.Value -> Result Json.Decode.Error AudioSource
decodeAudioSource note =
    let
        decoder =
            Json.Decode.map3
                AudioSource
                (Json.Decode.field "id" Json.Decode.int)
                (Json.Decode.field "node" Json.Decode.value)
                (Json.Decode.succeed Nothing)
    in
    note |> Json.Decode.decodeValue decoder


encodeGetWaveformsCommand : Dict Int AudioSource -> Json.Encode.Value
encodeGetWaveformsCommand nodes =
    nodes
        |> Dict.values
        |> Json.Encode.list
            (\node ->
                Json.Encode.object
                    [ ( "id", Json.Encode.int node.id )
                    , ( "node", node.node )
                    ]
            )


encodeGetFftsCommand : Dict Int AudioSource -> Json.Encode.Value
encodeGetFftsCommand nodes =
    nodes
        |> Dict.values
        |> Json.Encode.list
            (\node ->
                Json.Encode.object
                    [ ( "id", Json.Encode.int node.id )
                    , ( "node", node.node )
                    ]
            )
