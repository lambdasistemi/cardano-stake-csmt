{- |
Module      : Cardano.StakeCSMT.Application.Run.Main
Description : Application entrypoint wiring.

Runs the scaffold HTTP server with static health and readiness routes.
-}
module Cardano.StakeCSMT.Application.Run.Main
    ( RuntimeApplications (..)
    , applications
    , main
    , run
    , runWithHandlers
    , withRuntimeHandlers
    ) where

import Cardano.Crypto.DSIGN.Class
    ( SignKeyDSIGN
    )
import Cardano.Crypto.DSIGN.Ed25519
    ( Ed25519DSIGN
    )
import Cardano.StakeCSMT.Application.Run.CLI
    ( runtimeConfigFromCommandLine
    )
import Cardano.StakeCSMT.Application.Run.Config
    ( RuntimeConfig (..)
    , configApiPort
    )
import Cardano.StakeCSMT.CSMT.Columns qualified as Stake
import Cardano.StakeCSMT.CSMT.RocksDB
    ( mkStakeCSMTDatabase
    , withStakeCSMTRocksDB
    )
import Cardano.StakeCSMT.HTTP.API
    ( ReadyResponse (..)
    )
import Cardano.StakeCSMT.HTTP.Query qualified as Query
import Cardano.StakeCSMT.HTTP.Server
    ( QueryHandlers (..)
    , apiApp
    , docsApp
    , runAPIServer
    , runDocsServer
    )
import Cardano.StakeCSMT.History.Columns qualified as History
import Cardano.StakeCSMT.History.RocksDB
    ( mkHistoryDatabase
    , withHistoryRocksDB
    )
import Control.Concurrent
    ( forkIO
    )
import Control.Monad
    ( void
    )
import Database.KV.Database
    ( Database
    )
import Database.KV.Transaction
    ( runTransactionUnguarded
    )
import Database.RocksDB
    ( BatchOp
    , ColumnFamily
    )
import Network.Wai
    ( Application
    )

data RuntimeApplications = RuntimeApplications
    { runtimeApiApp :: Application
    , runtimeDocsApp :: Maybe Application
    }

main :: IO ()
main =
    runtimeConfigFromCommandLine >>= run

run :: RuntimeConfig -> IO ()
run config =
    withRuntimeHandlers config $ runWithHandlers config

runWithHandlers :: RuntimeConfig -> QueryHandlers -> IO ()
runWithHandlers config handlers = do
    case configDocsPort config of
        Nothing -> pure ()
        Just docsPort ->
            void
                $ forkIO
                $ runDocsServer
                    docsPort
                    (Just $ configApiPort config)
    runAPIServer (configApiPort config) handlers

applications :: RuntimeConfig -> QueryHandlers -> RuntimeApplications
applications config handlers =
    RuntimeApplications
        { runtimeApiApp = apiApp handlers
        , runtimeDocsApp =
            docsApp (Just $ fromIntegral $ configApiPort config)
                <$ configDocsPort config
        }

withRuntimeHandlers
    :: RuntimeConfig -> (QueryHandlers -> IO a) -> IO a
withRuntimeHandlers
    RuntimeConfig
        { configStakeDbPath
        , configHistoryDbPath
        , configSigningKey
        }
    action =
        withStakeCSMTRocksDB configStakeDbPath $ \stakeRocksDB ->
            withHistoryRocksDB configHistoryDbPath $ \historyRocksDB ->
                action
                    $ runtimeHandlers
                        (mkStakeCSMTDatabase stakeRocksDB)
                        (mkHistoryDatabase historyRocksDB)
                        configSigningKey

runtimeHandlers
    :: Database IO ColumnFamily Stake.Columns BatchOp
    -> Database IO ColumnFamily History.Columns BatchOp
    -> Maybe (SignKeyDSIGN Ed25519DSIGN)
    -> QueryHandlers
runtimeHandlers stakeDb historyDb mSigningKey =
    QueryHandlers
        { queryLatestProof =
            runTransactionUnguarded stakeDb . Query.queryLatestProof
        , queryHistoricalProof =
            \epoch credential ->
                runTransactionUnguarded stakeDb
                    $ Query.queryHistoricalProof epoch credential
        , queryEpochRoots =
            runTransactionUnguarded stakeDb Query.queryEpochRoots
        , queryLatestHeader =
            case mSigningKey of
                Nothing -> pure Nothing
                Just signingKey ->
                    runTransactionUnguarded stakeDb
                        $ Query.querySignedLatestHeader signingKey
        , queryHistoryRoot =
            runTransactionUnguarded historyDb Query.queryCurrentHistoryRoot
        , queryReady =
            pure ReadyResponse{ready = True}
        }
