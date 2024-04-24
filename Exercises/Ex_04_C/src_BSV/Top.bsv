// Build-and-run this program
// Try variations: change bit-widths and values of a and b
// Try variations: change all Bit #(n) to Int #(n)

(* synthesize *)
module mkTop (Empty);

   function Action print_V_V_Bool (String op, Bit #(4) a, Bit #(4) b, Bool result);
      $display ("  %s: %04b %04b => %d or ", op, a, b, result, fshow (result));
   endfunction

   // Note 'result' argument is polymorphic in bit-width
   function Action print_V_V (String op, Bit #(4) b, Bit #(n) result);
      $display ("  %s: %04b => %d or 0x%h", op, b, result, result);
   endfunction

   function Action print_V_V_V (String op, Bit #(4) a, Bit #(4) b, Bit #(4) result);
      $display ("  %s: %04b %04b => %d or 0x%0h", op, a, b, result, result);
   endfunction

   rule rl_once;
      Bit #(4) a = 'b_1010;    // use -5 for Int
      Bit #(4) b = 'b_0110;

      $display ("Some bitwise arithmetic ops");
      print_V_V_Bool ("==", a, b, a == b);
      print_V_V_Bool ("!=", a, b, a != b);
      print_V_V_Bool ("<", a, b, a < b);
      print_V_V_Bool (">", a, b, a > b);

      $display ("Some bitwise arithmetic ops");
      print_V_V_V ("+", a, b, a + b);
      print_V_V_V ("-", a, b, a - b);
      print_V_V_V ("*", a, b, a * b);

      $display ("Some bitwise logic ops");
      print_V_V_V ("&", a, b, a & b);
      print_V_V_V ("|", a, b, a | b);
      print_V_V ("~", b, ~ b);
      print_V_V_V ("^", a, b, a ^ b);

      $display ("Some shift ops");
      print_V_V ("<< 2", a, a << 2);
      print_V_V (">> 3", a, a >> 3);

      $display ("Some truncate/extend ops");
      Bit #(2) c = truncate (a);   print_V_V ("truncate  ", a, c);
      Bit #(6) d = extend (a);     print_V_V ("extend    ", a, d);
      Bit #(7) e = zeroExtend (a); print_V_V ("zeroExtend", a, e);
      Bit #(8) f = signExtend (a); print_V_V ("signExtend", a, f);

      $finish (0);
   endrule

endmodule
