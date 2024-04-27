// Build-and-run this program
// Try variations: change bit-widths and values of a and b

(* synthesize *)
module mkTop (Empty);

   function Action print_Bit_Bit_Bool (String op, Bit #(4) a, Bit #(4) b, Bool result);
      $display ("  %s: %04b %04b => %d or ", op, a, b, result, fshow (result));
   endfunction

   // Note 'result' argument is polymorphic in bit-width
   function Action print_Bit_Bit (String op, Bit #(4) b, Bit #(n) result);
      $display ("  %s: %04b => %d or 0x%h", op, b, result, result);
   endfunction

   function Action print_Bit_Bit_Bit (String op, Bit #(4) a, Bit #(4) b, Bit #(4) result);
      $display ("  %s: %04b %04b => %d or 0x%0h", op, a, b, result, result);
   endfunction

   rule rl_once;
      Bit #(4) a = 'b_1010;
      Bit #(4) b = 'b_0110;

      $display ("Some bitwise arithmetic ops");
      print_Bit_Bit_Bool ("==", a, b, a == b);
      print_Bit_Bit_Bool ("!=", a, b, a != b);
      print_Bit_Bit_Bool ("<", a, b, a < b);
      print_Bit_Bit_Bool (">", a, b, a > b);

      $display ("Some bitwise arithmetic ops");
      print_Bit_Bit_Bit ("+", a, b, a + b);
      print_Bit_Bit_Bit ("-", a, b, a - b);
      print_Bit_Bit_Bit ("*", a, b, a * b);

      $display ("Some bitwise logic ops");
      print_Bit_Bit_Bit ("&", a, b, a & b);
      print_Bit_Bit_Bit ("|", a, b, a | b);
      print_Bit_Bit ("~", b, ~ b);
      print_Bit_Bit_Bit ("^", a, b, a ^ b);

      $display ("Some shift ops");
      print_Bit_Bit ("<< 2", a, a << 2);
      print_Bit_Bit (">> 3", a, a >> 3);

      $display ("Some truncate/extend ops");
      Bit #(2) c = truncate (a);   print_Bit_Bit ("truncate  ", a, c);
      Bit #(6) d = extend (a);     print_Bit_Bit ("extend    ", a, d);
      Bit #(7) e = zeroExtend (a); print_Bit_Bit ("zeroExtend", a, e);
      Bit #(8) f = signExtend (a); print_Bit_Bit ("signExtend", a, f);

      $finish (0);
   endrule

endmodule
