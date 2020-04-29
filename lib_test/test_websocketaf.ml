module Websocket = struct
  open Websocketaf.Websocket

  module Testable = struct
    let opcode = Alcotest.testable Opcode.pp_hum (=)
  end

  let parse_frame serialized_frame =
    match Angstrom.parse_string Frame.parse serialized_frame with
    | Ok frame -> frame
    | Error err -> Alcotest.fail err

  let serialize_frame ~is_fin frame =
    let f = Faraday.create 0x100 in
    Frame.serialize_bytes
      f
      ~is_fin
      ~opcode:`Text
      ~payload:(Bytes.of_string frame)
      ~off:0
      ~len:(String.length frame);
    Faraday.serialize_to_string f

  let test_parsing_ping_frame () =
    let frame = parse_frame "\137\128\000\000\046\216" in
    Alcotest.check Testable.opcode "opcode" `Ping (Frame.opcode frame);
    Alcotest.(check bool) "has mask" true (Frame.has_mask frame);
    Alcotest.(check int32) "mask" 11992l (Frame.mask_exn frame);
    Alcotest.(check int) "payload_length" (Frame.payload_length frame) 0;
    Alcotest.(check int) "length" (Frame.length frame) 6

  let test_parsing_close_frame () =
    let frame = parse_frame "\136\000" in
    Alcotest.check Testable.opcode "opcode" `Connection_close (Frame.opcode frame);
    Alcotest.(check int) "payload_length" (Frame.payload_length frame) 0;
    Alcotest.(check int) "length" (Frame.length frame) 2;
    Alcotest.(check bool) "is_fin" true (Frame.is_fin frame)

  let test_parsing_text_frame () =
    let frame = parse_frame "\129\139\086\057\046\216\103\011\029\236\099\015\025\224\111\009\036" in
    Alcotest.check Testable.opcode "opcode" `Text (Frame.opcode frame);
    Alcotest.(check bool) "has mask" true (Frame.has_mask frame);
    Alcotest.(check int32) "mask" 1446588120l (Frame.mask_exn frame);
    Alcotest.(check int) "payload_length" (Frame.payload_length frame) 11;
    Alcotest.(check int) "length" (Frame.length frame) 17;
    Frame.unmask_inplace frame;
    Alcotest.(check bool) "is_fin" true (Frame.is_fin frame);
    let payload = Bytes.to_string (Frame.copy_payload_bytes frame) in
    Alcotest.(check string) "payload" "1234567890\n" payload

  let test_parsing_fin_bit () =
   let frame = parse_frame (serialize_frame ~is_fin:false "hello") in
    Alcotest.check Testable.opcode "opcode" `Text (Frame.opcode frame);
    Alcotest.(check bool) "is_fin" false (Frame.is_fin frame);
   let frame = parse_frame (serialize_frame ~is_fin:true "hello") in
    Alcotest.check Testable.opcode "opcode" `Text (Frame.opcode frame);
    Alcotest.(check bool) "is_fin" true (Frame.is_fin frame);
    let payload = Bytes.to_string (Frame.copy_payload_bytes frame) in
    Alcotest.(check string) "payload" "hello" payload

  let tests =
    [ "parsing ping frame",  `Quick, test_parsing_ping_frame
    ; "parsing close frame", `Quick, test_parsing_close_frame
    ; "parsing text frame",  `Quick, test_parsing_text_frame
    ; "parsing fin bit",  `Quick, test_parsing_fin_bit
    ]
end

let () =
  Alcotest.run "websocketaf unit tests"
    [ "websocket", Websocket.tests
    ]
