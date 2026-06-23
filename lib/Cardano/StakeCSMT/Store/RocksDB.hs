{- |
Module      : Cardano.StakeCSMT.Store.RocksDB
Description : RocksDB helpers for the unified stake CSMT store.

Opens one RocksDB instance containing both stake CSMT and history accumulator
column families.
-}
module Cardano.StakeCSMT.Store.RocksDB
    ( mkStoreDatabase
    , withStoreRocksDB
    )
where

import Cardano.StakeCSMT.Store.Columns
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

-- | Open a RocksDB handle with all stake and history column families.
withStoreRocksDB :: FilePath -> (DB -> IO a) -> IO a
withStoreRocksDB path =
    withDBCF path storeConfig storeColumnFamilies

-- | Adapt an open RocksDB handle to the unified typed database.
mkStoreDatabase :: DB -> Database IO ColumnFamily Columns BatchOp
mkStoreDatabase db =
    mkRocksDBDatabase db $ mkColumns (columnFamilies db) codecs

storeColumnFamilies :: [(String, Config)]
storeColumnFamilies =
    [ ("snapshot", storeConfig)
    , ("tree", storeConfig)
    , ("root", storeConfig)
    , ("history-leaf", storeConfig)
    , ("history-tree", storeConfig)
    , ("history-root", storeConfig)
    ]

storeConfig :: Config
storeConfig =
    Config
        { createIfMissing = True
        , errorIfExists = False
        , paranoidChecks = False
        , maxFiles = Nothing
        , prefixLength = Nothing
        , bloomFilter = False
        }
