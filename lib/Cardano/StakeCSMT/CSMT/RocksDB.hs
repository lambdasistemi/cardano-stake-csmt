{- |
Module      : Cardano.StakeCSMT.CSMT.RocksDB
Description : RocksDB database helpers for stake CSMT columns.

Thin helpers for opening the stake CSMT RocksDB column families and adapting
them to the typed key-value database interface used by the CSMT builder.
-}
module Cardano.StakeCSMT.CSMT.RocksDB
    ( mkStakeCSMTDatabase
    , withStakeCSMTRocksDB
    )
where

import Cardano.StakeCSMT.CSMT.Columns
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

-- | Open a RocksDB handle with the stake CSMT column families.
withStakeCSMTRocksDB :: FilePath -> (DB -> IO a) -> IO a
withStakeCSMTRocksDB path =
    withDBCF path stakeCSMTConfig stakeCSMTColumnFamilies

-- | Adapt an open RocksDB handle to the stake CSMT typed database.
mkStakeCSMTDatabase :: DB -> Database IO ColumnFamily Columns BatchOp
mkStakeCSMTDatabase db =
    mkRocksDBDatabase db $ mkColumns (columnFamilies db) codecs

stakeCSMTColumnFamilies :: [(String, Config)]
stakeCSMTColumnFamilies =
    [ ("snapshot", stakeCSMTConfig)
    , ("tree", stakeCSMTConfig)
    , ("root", stakeCSMTConfig)
    ]

stakeCSMTConfig :: Config
stakeCSMTConfig =
    Config
        { createIfMissing = True
        , errorIfExists = False
        , paranoidChecks = False
        , maxFiles = Nothing
        , prefixLength = Nothing
        , bloomFilter = False
        }
