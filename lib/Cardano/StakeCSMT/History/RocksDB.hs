{- |
Module      : Cardano.StakeCSMT.History.RocksDB
Description : RocksDB database helpers for history accumulator columns.

Thin helpers for opening the history accumulator RocksDB column families and
adapting them to the typed key-value database interface used by the history
builder.
-}
module Cardano.StakeCSMT.History.RocksDB
    ( mkHistoryDatabase
    , withHistoryRocksDB
    )
where

import Cardano.StakeCSMT.History.Columns
    ( Columns
    , codecs
    )
import Database.KV.Database
    ( Database
    , mkColumns
    )
import Database.KV.RocksDB
    ( mkRocksDBDatabase
    )
import Database.RocksDB
    ( BatchOp
    , ColumnFamily
    , Config (..)
    , DB
    , columnFamilies
    , withDBCF
    )

-- | Open a RocksDB handle with the history accumulator column families.
withHistoryRocksDB :: FilePath -> (DB -> IO a) -> IO a
withHistoryRocksDB path =
    withDBCF path historyConfig historyColumnFamilies

-- | Adapt an open RocksDB handle to the history accumulator typed database.
mkHistoryDatabase :: DB -> Database IO ColumnFamily Columns BatchOp
mkHistoryDatabase db =
    mkRocksDBDatabase db $ mkColumns (columnFamilies db) codecs

historyColumnFamilies :: [(String, Config)]
historyColumnFamilies =
    [ ("history-leaf", historyConfig)
    , ("history-tree", historyConfig)
    , ("history-root", historyConfig)
    ]

historyConfig :: Config
historyConfig =
    Config
        { createIfMissing = True
        , errorIfExists = False
        , paranoidChecks = False
        , maxFiles = Nothing
        , prefixLength = Nothing
        , bloomFilter = False
        }
