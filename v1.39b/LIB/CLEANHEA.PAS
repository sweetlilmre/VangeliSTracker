{****************************************************************************}
{                                                                            }
{ MODULE:         CleanHeap                                                  }
{                                                                            }
{ DESCRIPTION:    UNIT used to debug uninitialized variables in the Heap     }
{                 and Uninitialized Data Segment. Use with caution.          }
{                                                                            }
{ AUTHOR:         Juan Carlos Ar‚valo                                        }
{                                                                            }
{ MODIFICATIONS:  Nobody (yet ;-)                                            }
{                                                                            }
{ HISTORY:        27-Jan-1993 Definition, creation and first use.            }
{                                                                            }
{ (C) 1993 VangeliSTeam                                                      }
{____________________________________________________________________________}

UNIT CleanHeap;

INTERFACE




TYPE
  TBuff = ARRAY[1..65520] OF BYTE;
VAR
  HPtr  : ^TBuff;
  BSize : WORD;




IMPLEMENTATION




{
BEGIN

  HPtr := HeapPtr;

  WHILE HPtr <> HeapEnd DO
    BEGIN
      FillChar(HPtr^, 16, $00);
      HPtr := Ptr(SEG(HPtr^)+1, OFS(HPtr^));
    END;

  HPtr  := Ptr(SEG(Test8087), OFS(Test8087) + 1);

  BSize := OFS(BSize) - 4 - OFS(Test8087) + 1;
  FillChar(HPtr^, BSize, 0);
}
{
  BSize := OFS(BSize) - 4 - OFS(Test8087) + 1;
  HPtr  := Ptr(SEG(HPtr^), OFS(HPtr^) + BSize - BSize DIV 8
                                              + BSize DIV 32
                                              + BSize DIV 64
                                              + BSize DIV 128);
  FillChar(HPtr^, BSize DIV 2048, 0);
}

END.
