module Cardano.StakeCSMT.E2E.ReplaySpec
    ( spec
    ) where

import Cardano.Node.Client.E2E.Devnet
    ( withCardanoNode
    )
import Cardano.StakeCSMT.Ledger.Config
    ( ledgerConfigPathsFromDirectory
    , loadLedgerConfig
    )
import Cardano.StakeCSMT.Ledger.Replay
    ( ReplayFollowerConfig (..)
    , defaultReplayChainSyncRunner
    , replayBlock
    , runReplayFollowerWith
    )
import Data.IORef
    ( modifyIORef'
    , newIORef
    , readIORef
    )
import Data.List
    ( nub
    )
import Ouroboros.Network.Magic
    ( NetworkMagic (..)
    )
import System.FilePath
    ( takeDirectory
    )
import System.Timeout
    ( timeout
    )
import Test.Hspec
    ( Spec
    , describe
    , expectationFailure
    , it
    , shouldBe
    , shouldSatisfy
    )

genesisDir :: FilePath
genesisDir = "e2e-test/genesis"

spec :: Spec
spec =
    describe "Replay devnet proof"
        $ it "replays devnet chain sync blocks to tip without error"
        $ withCardanoNode genesisDir
        $ \socketPath _startMs -> do
            let nodeRuntimeDir = takeDirectory socketPath
                config =
                    ReplayFollowerConfig
                        { replayFollowerSocketPath = socketPath
                        , replayFollowerNetworkMagic = NetworkMagic 42
                        , replayFollowerByronEpochSlots = 21_600
                        }
            bundle <-
                loadLedgerConfig
                    $ ledgerConfigPathsFromDirectory nodeRuntimeDir
            blockCountRef <- newIORef (0 :: Int)
            transitionsRef <- newIORef []
            let recordEpochTransition transition =
                    modifyIORef' transitionsRef (transition :)
                replayAction state block = do
                    nextState <-
                        replayBlock
                            bundle
                            recordEpochTransition
                            state
                            block
                    modifyIORef' blockCountRef (+ 1)
                    pure nextState

            result <-
                timeout 15_000_000
                    $ runReplayFollowerWith
                        defaultReplayChainSyncRunner
                        replayAction
                        bundle
                        config

            case result of
                Just (Left err) ->
                    expectationFailure
                        $ "expected replay follower not to fail, got "
                            <> show err
                _ ->
                    pure ()
            blockCount <- readIORef blockCountRef
            blockCount `shouldSatisfy` (> 0)
            transitions <- readIORef transitionsRef
            transitions `shouldBe` nub transitions
