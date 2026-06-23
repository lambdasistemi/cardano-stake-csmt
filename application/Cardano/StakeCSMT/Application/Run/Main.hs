{- |
Module      : Cardano.StakeCSMT.Application.Run.Main
Description : Application entrypoint wiring.

Runs the scaffold HTTP server with static health and readiness routes.
-}
module Cardano.StakeCSMT.Application.Run.Main
    ( RuntimeApplications (..)
    , RuntimeIndexerAction
    , RuntimeReadinessSignal
    , RuntimeStoreDatabase
    , applications
    , main
    , markRuntimeReady
    , newRuntimeReadinessSignal
    , run
    , runWithHandlers
    , withRuntimeHandlers
    , withRuntimeHandlersUsingIndexer
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
import Cardano.StakeCSMT.Indexer
    ( EpochBoundaryHook
    , runIndexer
    )
import Cardano.StakeCSMT.Ledger.Config
    ( ledgerConfigPathsFromDirectory
    , loadLedgerConfig
    )
import Cardano.StakeCSMT.Ledger.Replay
    ( ReplayCheckpointConfig (..)
    , ReplayFollowerConfig (..)
    )
import Cardano.StakeCSMT.Store.Columns qualified as Store
import Cardano.StakeCSMT.Store.RocksDB
    ( mkStoreDatabase
    , withStoreRocksDB
    )
import Control.Concurrent
    ( ThreadId
    , forkFinally
    , forkIO
    , killThread
    , myThreadId
    , throwTo
    )
import Control.Exception
    ( Exception
    , SomeException
    , finally
    , try
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
import Data.Maybe
    ( fromMaybe
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
import Ouroboros.Network.Magic
    ( NetworkMagic (..)
    )
import System.Directory
    ( createDirectoryIfMissing
    )

data RuntimeApplications = RuntimeApplications
    { runtimeApiApp :: Application
    , runtimeDocsApp :: Maybe Application
    }

type RuntimeStoreDatabase =
    Database IO ColumnFamily Store.Columns BatchOp

type RuntimeIndexerAction =
    RuntimeStoreDatabase
    -> EpochBoundaryHook
    -> IO (Either SomeException ())

newtype RuntimeReadinessSignal = RuntimeReadinessSignal (IORef Bool)

data RuntimeIndexerTerminatedUnexpectedly
    = RuntimeIndexerTerminatedUnexpectedly
    deriving stock (Show)

instance Exception RuntimeIndexerTerminatedUnexpectedly

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
run config = do
    readiness <- newRuntimeReadinessSignal
    ledgerConfig <-
        loadLedgerConfig
            $ ledgerConfigPathsFromDirectory
            $ configLedgerConfigDir config
    checkpointConfig <- runtimeReplayCheckpointConfig config
    let followerConfig = runtimeReplayFollowerConfig config
        indexerAction storeDb hook =
            runIndexer
                ledgerConfig
                storeDb
                followerConfig
                checkpointConfig
                (Just hook)
    withRuntimeHandlersUsingIndexer
        readiness
        config
        indexerAction
        $ runWithHandlers config

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
    config
    action =
        withRuntimeStoreHandlers readiness config $ \_storeDb handlers ->
            action handlers

withRuntimeHandlersUsingIndexer
    :: RuntimeReadinessSignal
    -> RuntimeConfig
    -> RuntimeIndexerAction
    -> (QueryHandlers -> IO a)
    -> IO a
withRuntimeHandlersUsingIndexer readiness config indexerAction action =
    withRuntimeStoreHandlers readiness config $ \storeDb handlers ->
        withLinkedIndexer readiness storeDb indexerAction
            $ action handlers

withRuntimeStoreHandlers
    :: RuntimeReadinessSignal
    -> RuntimeConfig
    -> (RuntimeStoreDatabase -> QueryHandlers -> IO a)
    -> IO a
withRuntimeStoreHandlers
    readiness
    RuntimeConfig
        { configDbPath
        , configSigningKey
        }
    action =
        withStoreRocksDB configDbPath $ \rocksDB ->
            let storeDb = mkStoreDatabase rocksDB
            in  action
                    storeDb
                    $ runtimeHandlers
                        readiness
                        (Store.stakeDatabase storeDb)
                        (Store.historyDatabase storeDb)
                        configSigningKey

withLinkedIndexer
    :: RuntimeReadinessSignal
    -> RuntimeStoreDatabase
    -> RuntimeIndexerAction
    -> IO a
    -> IO a
withLinkedIndexer readiness storeDb indexerAction action = do
    foreground <- myThreadId
    stopping <- newIORef False
    indexerThread <-
        forkFinally
            ( normaliseIndexerResult
                $ indexerAction storeDb
                $ markReadyAfterIndexedEpoch readiness
            )
            (propagateIndexerExit stopping foreground)
    action
        `finally` do
            atomicWriteIORef stopping True
            killThread indexerThread

markReadyAfterIndexedEpoch
    :: RuntimeReadinessSignal -> EpochBoundaryHook
markReadyAfterIndexedEpoch readiness _transition = \case
    Nothing ->
        pure ()
    Just _indexed ->
        markRuntimeReady readiness

normaliseIndexerResult
    :: IO (Either SomeException ())
    -> IO (Either SomeException ())
normaliseIndexerResult action = do
    result <-
        try action
            :: IO (Either SomeException (Either SomeException ()))
    pure $ case result of
        Left exception ->
            Left exception
        Right indexerResult ->
            indexerResult

propagateIndexerExit
    :: IORef Bool
    -> ThreadId
    -> Either SomeException (Either SomeException ())
    -> IO ()
propagateIndexerExit stopping foreground result = do
    stoppingNow <- readIORef stopping
    case result of
        Left exception ->
            propagateFailure stoppingNow exception
        Right (Left exception) ->
            propagateFailure stoppingNow exception
        Right (Right ()) ->
            if stoppingNow
                then pure ()
                else throwTo foreground RuntimeIndexerTerminatedUnexpectedly
  where
    propagateFailure stoppingNow exception =
        if stoppingNow
            then pure ()
            else throwTo foreground exception

runtimeReplayFollowerConfig :: RuntimeConfig -> ReplayFollowerConfig
runtimeReplayFollowerConfig RuntimeConfig{..} =
    ReplayFollowerConfig
        { replayFollowerSocketPath = configNodeSocketPath
        , replayFollowerNetworkMagic = NetworkMagic configNetworkMagic
        , replayFollowerByronEpochSlots = configByronEpochSlots
        }

runtimeReplayCheckpointConfig
    :: RuntimeConfig -> IO ReplayCheckpointConfig
runtimeReplayCheckpointConfig RuntimeConfig{..} = do
    createDirectoryIfMissing True checkpointDirectory
    -- ReplayState serialization is not exposed; metadata checkpoints are
    -- still persisted, while state recovery deterministically falls back to
    -- replay reset.
    pure
        ReplayCheckpointConfig
            { replayCheckpointDirectory = checkpointDirectory
            , replayCheckpointTailLimit =
                fromIntegral $ min configByronEpochSlots 21_600
            , replayCheckpointCadence = configByronEpochSlots
            , replayCheckpointSaveState = \_checkpoint _state -> pure ()
            , replayCheckpointLoadState = \_checkpoint -> pure Nothing
            }
  where
    checkpointDirectory =
        fromMaybe
            (configDbPath <> "-checkpoints")
            configCheckpointDir

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
