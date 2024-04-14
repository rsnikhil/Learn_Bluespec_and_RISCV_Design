package DUT;

export DUT_IFC (..), mkDUT;

String title   = "The C Programming Language";
String authors = "Kernighan and Ritchie";

Bit #(11) year = 1978;

Bit #(4)  month = 2;

Bit #(5)  day = 22;

interface DUT_IFC;
   method Tuple2 #(String, String)                m_title_authors;
   method Tuple3 #(Bit #(11), Bit #(4), Bit #(5)) m_date;
endinterface

module mkDUT (DUT_IFC);
   method m_title_authors = tuple2 (title, authors);
   method m_date          = tuple3 (year, month, day);
endmodule

endpackage
