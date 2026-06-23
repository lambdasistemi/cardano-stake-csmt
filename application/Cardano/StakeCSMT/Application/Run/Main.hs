{- |
Module      : Cardano.StakeCSMT.Application.Run.Main
Description : Application entrypoint wiring.

Runs the scaffold HTTP server with static health and readiness routes.
-}
module Cardano.StakeCSMT.Application.Run.Main
    ( RuntimeApplications (..)
    , RuntimeReadinessSignal
    , applications
    , main
    , markRuntimeReady
    , newRuntimeReadinessSignal
    , run
    , runWithHandlers
    , withRuntimeHandlers
    , withRuntimeHandlersUsingReadiness
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
import Cardano.StakeCSMT.Store.Columns
    ( historyDatabase
    , stakeDatabase
    )
import Cardano.StakeCSMT.Store.RocksDB
    ( mkStoreDatabase
    , withStoreRocksDB
    )
import Control.Concurrent
    ( forkIO
    )
import Control.Monad
    ( void
    )
import Data.IORef
    ( IORef
    , atomicWriteIORef
    , newIORef
    , readIORef
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

newtype RuntimeReadinessSignal = RuntimeReadinessSignal (IORef Bool)

newRuntimeReadinessSignal :: IO RuntimeReadinessSignal
newRuntimeReadinessSignal =
    RuntimeReadinessSignal <$> newIORef False

markRuntimeReady :: RuntimeReadinessSignal -> IO ()
markRuntimeReady (RuntimeReadinessSignal readyRef) =
    atomicWriteIORef readyRef True

queryRuntimeReady :: RuntimeReadinessSignal -> IO ReadyResponse
queryRuntimeReady (RuntimeReadinessSignal readyRef) =
    ReadyResponse <$> readIORef readyRef

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
withRuntimeHandlers config action = do
    readiness <- newRuntimeReadinessSignal
    withRuntimeHandlersUsingReadiness readiness config action

withRuntimeHandlersUsingReadiness
    :: RuntimeReadinessSignal
    -> RuntimeConfig
    -> (QueryHandlers -> IO a)
    -> IO a
withRuntimeHandlersUsingReadiness
    readiness
    RuntimeConfig
        { configDbPath
        , configSigningKey
        }
    action =
        withStoreRocksDB configDbPath $ \rocksDB ->
            let storeDb = mkStoreDatabase rocksDB
            in  action
                    $ runtimeHandlers
                        readiness
                        (stakeDatabase storeDb)
                        (historyDatabase storeDb)
                        configSigningKey

runtimeHandlers
    :: RuntimeReadinessSignal
    -> Database IO ColumnFamily Stake.Columns BatchOp
    -> Database IO ColumnFamily History.Columns BatchOp
    -> Maybe (SignKeyDSIGN Ed25519DSIGN)
    -> QueryHandlers
runtimeHandlers readiness stakeDb historyDb mSigningKey =
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
            queryRuntimeReady readiness
        }
