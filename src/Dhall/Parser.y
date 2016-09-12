{
-- | Parsing logic for the Dhall language

{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE OverloadedStrings  #-}

module Dhall.Parser (
    -- * Parser
      exprFromBytes
    ) where

import Control.Exception (Exception)
import Data.ByteString.Lazy (ByteString)
import Data.Text.Lazy (Text)
import Data.Typeable (Typeable)
import Dhall.Core
import Dhall.Lexer (Alex, Token)

import qualified Data.Map
import qualified Data.Vector
import qualified Data.Text.Lazy
import qualified Dhall.Lexer
}

%name expr
%tokentype { Token }
%error { parseError }
%lexer { Dhall.Lexer.lexer } { Dhall.Lexer.EOF }
%monad { Alex }

%token
    '('            { Dhall.Lexer.OpenParen        }
    ')'            { Dhall.Lexer.CloseParen       }
    '{'            { Dhall.Lexer.OpenBrace        }
    '}'            { Dhall.Lexer.CloseBrace       }
    '{{'           { Dhall.Lexer.DoubleOpenBrace  }
    '}}'           { Dhall.Lexer.DoubleCloseBrace }
    '['            { Dhall.Lexer.OpenBracket      }
    ']'            { Dhall.Lexer.CloseBracket     }
    ':'            { Dhall.Lexer.Colon            }
    ','            { Dhall.Lexer.Comma            }
    '.'            { Dhall.Lexer.Dot              }
    '='            { Dhall.Lexer.Equals           }
    '&&'           { Dhall.Lexer.And              }
    '||'           { Dhall.Lexer.Or               }
    '+'            { Dhall.Lexer.Plus             }
    '++'           { Dhall.Lexer.DoublePlus       }
    '-'            { Dhall.Lexer.Dash             }
    '*'            { Dhall.Lexer.Star             }
    'let'          { Dhall.Lexer.Let              }
    'in'           { Dhall.Lexer.In               }
    'Type'         { Dhall.Lexer.Type             }
    'Kind'         { Dhall.Lexer.Kind             }
    '->'           { Dhall.Lexer.Arrow            }
    'forall'       { Dhall.Lexer.Forall           }
    '\\'           { Dhall.Lexer.Lambda           }
    'Bool'         { Dhall.Lexer.Bool             }
    'True'         { Dhall.Lexer.True_            }
    'False'        { Dhall.Lexer.False_           }
    'if'           { Dhall.Lexer.If               }
    'then'         { Dhall.Lexer.Then             }
    'else'         { Dhall.Lexer.Else             }
    'Natural'      { Dhall.Lexer.Natural          }
    'Natural/fold' { Dhall.Lexer.NaturalFold      }
    'Integer'      { Dhall.Lexer.Integer          }
    'Double'       { Dhall.Lexer.Double           }
    'Text'         { Dhall.Lexer.Text             }
    'Maybe'        { Dhall.Lexer.Maybe            }
    'Nothing'      { Dhall.Lexer.Nothing_         }
    'Just'         { Dhall.Lexer.Just_            }
    'List/build'   { Dhall.Lexer.ListBuild        }
    'List/fold'    { Dhall.Lexer.ListFold         }
    text           { Dhall.Lexer.TextLit    $$    }
    label          { Dhall.Lexer.Label      $$    }
    number         { Dhall.Lexer.Number     $$    }
    double         { Dhall.Lexer.DoubleLit  $$    }
    natural        { Dhall.Lexer.NaturalLit $$    }
    url            { Dhall.Lexer.URL        $$    }
    file           { Dhall.Lexer.File       $$    }

%%

Expr0
    : Expr2 ':' Expr1
        { Annot $1 $3 }
    | Expr1
        { $1 }

Expr1
    : Expr2
        { $1 }
    | '\\' '(' label ':' Expr1 ')' '->' Expr0
        { Lam $3 $5 $8 }
    | 'forall' '(' label ':' Expr1 ')' '->' Expr0
        { Pi $3 $5 $8 }
    | Expr2 '->' Expr0
        { Pi "_" $1 $3 }
    | '-' number
        { IntegerLit (negate (fromIntegral $2)) }
    | Lets 'in' Expr0
        { Lets $1 $3 }

Expr2
    : Expr2 Expr3
        { App $1 $2 }
    | 'Maybe' Expr2
        { Maybe $2 }
    | Expr2 '&&' Expr2
        { BoolAnd $1 $3 }
    | Expr2 '||' Expr2
        { BoolOr $1 $3 }
    | Expr2 '+' Expr2
        { NaturalPlus $1 $3 }
    | Expr2 '*' Expr2
        { NaturalTimes $1 $3 }
    | Expr2 '++' Expr2
        { TextAppend $1 $3 }
    | Expr3
        { $1 }

Expr3
    : label
        { Var $1 }
    | 'Type'
        { Const Star }
    | 'Kind'
        { Const Box }
    | 'Bool'
        { Bool }
    | 'Natural'
        { Natural }
    | 'Natural/fold'
        { NaturalFold }
    | 'Integer'
        { Integer }
    | 'Double'
        { Double }
    | 'Text'
        { Text }
    | 'Nothing'
        { Nothing_ }
    | 'Just'
        { Just_ }
    | 'List/build'
        { ListBuild }
    | 'List/fold'
        { ListFold }
    | '[' Expr1 ']'
        { List $2 }
    | 'True'
        { BoolLit True }
    | 'False'
        { BoolLit False }
    | number
        { IntegerLit (fromIntegral $1) }
    | natural
        { NaturalLit $1 }
    | double
        { DoubleLit $1 }
    | text
        { TextLit $1 }
    | '[' Elems ':' Expr1 ']'
        { ListLit $4 (Data.Vector.fromList $2) }
    | RecordLit
        { $1 }
    | Record
        { $1 }
    | 'if' Expr0 'then' Expr0 'else' Expr0
        { BoolIf $2 $4 $6 }
    | Import
        { Embed $1 }
    | Expr3 '.' label
        { Field $1 $3 }
    | '(' Expr0 ')'
        { $2 }
    
Lets
    : LetsRev
        { reverse $1 }

LetsRev
    : Let
        { [$1] }
    | LetsRev Let
        { $2 : $1 }

Let
    : 'let' label Args '=' Expr0
        { Let $2 $3 $5 }

Args
    : ArgsRev
        { reverse $1 }

ArgsRev
    : {- empty -}
        { [] }
    | ArgsRev Arg
        { $2 : $1 }

Arg
    : '(' label ':' Expr1 ')'
        { ($2, $4) }

Elems
    : ElemsRev
        { reverse $1 }

ElemsRev
    : Expr1
        { [$1] }
    | ElemsRev ',' Expr1
        { $3 : $1 }

RecordLit
    : '{' FieldValues '}'
        { RecordLit (Data.Map.fromList $2) }

FieldValues
    : FieldValuesRev
        { reverse $1 }

FieldValuesRev
    : {- empty -}
        { [] }
    | FieldValue
        { [$1] }
    | FieldValuesRev ',' FieldValue
        { $3 : $1 }

FieldValue
    : label '=' Expr0 
        { ($1, $3) }

Record
    : '{{' FieldTypes '}}' 
        { Record (Data.Map.fromList $2) }

FieldTypes
    : FieldTypesRev
        { reverse $1 }

FieldTypesRev
    : {- empty -}
        { [] }
    | FieldType
        { [$1] }
    | FieldTypesRev ',' FieldType
        { $3 : $1 }

FieldType
    : label ':' Expr1
        { ($1, $3) } 

Import
    : file
        { File $1 }
    | url
        { URL $1 }

{
parseError :: Token -> Alex a
parseError token = Dhall.Lexer.alexError (show token)

newtype ParseError = ParseError Text
    deriving (Typeable)

instance Show ParseError where
    show (ParseError txt) = show txt

instance Exception ParseError

exprFromBytes :: ByteString -> Either ParseError (Expr Path)
exprFromBytes bytes = case Dhall.Lexer.runAlex bytes expr of
    Left  str -> Left (ParseError (Data.Text.Lazy.pack str))
    Right e   -> Right e
}