module Cardano.StakeCSMT.Ledger.CheckpointSpec
    ( spec
    ) where

import Cardano.Node.Client.N2C.ChainSync
    ( Fetched (..)
    )
import Cardano.Node.Client.Types
    ( Block
    )
import Cardano.Slotting.Slot
    ( SlotNo (..)
    )
import Cardano.StakeCSMT.Ledger.Checkpoint
    ( CheckpointPoint (..)
    , ReplayCheckpoint (..)
    , ReplayTail
    , appendReplayTailAt
    , checkpointPointFromHeaderPoint
    , decodeReplayCheckpoint
    , emptyReplayTail
    , encodeReplayCheckpoint
    , listReplayCheckpoints
    , loadReplayCheckpoint
    , nearestCheckpointAtOrBefore
    , recoverReplayTail
    , replayTailFetched
    , saveReplayCheckpoint
    , truncateReplayTailAfter
    )
import Data.Word
    ( Word64
    )
import Ouroboros.Network.Block qualified as Network
import Ouroboros.Network.Point qualified as Network.Point
import System.IO.Temp
    ( withSystemTempDirectory
    )
import Test.Hspec
    ( Spec
    , describe
    , expectationFailure
    , it
    , shouldBe
    )
import Unsafe.Coerce
    ( unsafeCoerce
    )

spec :: Spec
spec =
    describe "Ledger.Checkpoint" $ do
        it "round-trips finalized-boundary checkpoint metadata" $ do
            let checkpoint =
                    ReplayCheckpoint
                        { replayCheckpointPoint = CheckpointAtBlock 42
                        , replayCheckpointFinalizedEpoch = 6
                        , replayCheckpointObservedEpoch = 7
                        }

            decoded <-
                expectRight
                    $ decodeReplayCheckpoint
                    $ encodeReplayCheckpoint checkpoint

            decoded `shouldBe` checkpoint

        it "saves, lists, and loads checkpoints from a directory" $ do
            let checkpoint =
                    ReplayCheckpoint
                        { replayCheckpointPoint = CheckpointAtBlock 42
                        , replayCheckpointFinalizedEpoch = 6
                        , replayCheckpointObservedEpoch = 7
                        }

            withSystemTempDirectory "stake-csmt-checkpoints" $ \directory -> do
                _ <- saveReplayCheckpoint directory checkpoint

                points <- listReplayCheckpoints directory
                points `shouldBe` [CheckpointAtBlock 42]

                loaded <-
                    expectRight
                        =<< loadReplayCheckpoint
                            directory
                            (CheckpointAtBlock 42)
                loaded `shouldBe` checkpoint

        it "selects the nearest checkpoint at or before a rollback point" $ do
            let points =
                    [ CheckpointAtBlock 30
                    , CheckpointOrigin
                    , CheckpointAtBlock 10
                    , CheckpointAtBlock 20
                    ]

            nearestCheckpointAtOrBefore points (CheckpointAtBlock 25)
                `shouldBe` Just (CheckpointAtBlock 20)
            nearestCheckpointAtOrBefore points (CheckpointAtBlock 30)
                `shouldBe` Just (CheckpointAtBlock 30)
            nearestCheckpointAtOrBefore points CheckpointOrigin
                `shouldBe` Just CheckpointOrigin
            nearestCheckpointAtOrBefore [CheckpointAtBlock 10] CheckpointOrigin
                `shouldBe` Nothing

        it "converts origin header points into checkpoint metadata" $ do
            checkpointPointFromHeaderPoint
                (Network.Point Network.Point.Origin)
                `shouldBe` CheckpointOrigin

        it "truncates and recovers bounded replay tails" $ do
            let tail0 = emptyReplayTail
                tail1 =
                    appendReplayTailAt
                        3
                        (CheckpointAtBlock 1)
                        (fetchedWithTip 1)
                        tail0
                tail2 =
                    appendReplayTailAt
                        3
                        (CheckpointAtBlock 2)
                        (fetchedWithTip 2)
                        tail1
                tail3 =
                    appendReplayTailAt
                        3
                        (CheckpointAtBlock 3)
                        (fetchedWithTip 3)
                        tail2
                tail4 =
                    appendReplayTailAt
                        3
                        (CheckpointAtBlock 4)
                        (fetchedWithTip 4)
                        tail3

            tailTips tail4 `shouldBe` [SlotNo 2, SlotNo 3, SlotNo 4]
            tailTips (truncateReplayTailAfter (CheckpointAtBlock 3) tail4)
                `shouldBe` [SlotNo 2, SlotNo 3]
            recoverTips
                (recoverReplayTail (CheckpointAtBlock 2) (CheckpointAtBlock 4) tail4)
                `shouldBe` Just [SlotNo 3, SlotNo 4]
            recoverTips
                (recoverReplayTail (CheckpointAtBlock 4) (CheckpointAtBlock 4) tail4)
                `shouldBe` Just []
            recoverTips
                (recoverReplayTail (CheckpointAtBlock 2) (CheckpointAtBlock 5) tail4)
                `shouldBe` Nothing

        it
            "rejects recovery when the boundary predates the oldest retained block"
            $ do
                let tail0 = emptyReplayTail
                    tail1 =
                        appendReplayTailAt
                            3
                            (CheckpointAtBlock 1)
                            (fetchedWithTip 1)
                            tail0
                    tail2 =
                        appendReplayTailAt
                            3
                            (CheckpointAtBlock 2)
                            (fetchedWithTip 2)
                            tail1
                    tail3 =
                        appendReplayTailAt
                            3
                            (CheckpointAtBlock 3)
                            (fetchedWithTip 3)
                            tail2
                    tail4 =
                        appendReplayTailAt
                            3
                            (CheckpointAtBlock 4)
                            (fetchedWithTip 4)
                            tail3

                tailTips tail4 `shouldBe` [SlotNo 2, SlotNo 3, SlotNo 4]
                recoverTips
                    (recoverReplayTail (CheckpointAtBlock 1) (CheckpointAtBlock 1) tail4)
                    `shouldBe` Just []
                recoverTips
                    (recoverReplayTail (CheckpointAtBlock 1) (CheckpointAtBlock 4) tail4)
                    `shouldBe` Nothing
                recoverTips
                    (recoverReplayTail CheckpointOrigin (CheckpointAtBlock 4) tail4)
                    `shouldBe` Nothing

fetchedWithTip :: Word64 -> Fetched
fetchedWithTip slot =
    Fetched
        { fetchedPoint = Network.Point Network.Point.Origin
        , fetchedBlock = fakeBlock
        , fetchedTip = SlotNo slot
        }

fakeBlock :: Block
fakeBlock =
    unsafeCoerce ()

tailTips :: ReplayTail -> [SlotNo]
tailTips tailValue =
    fetchedTip <$> replayTailFetched tailValue

recoverTips :: Maybe [Fetched] -> Maybe [SlotNo]
recoverTips fetched =
    fmap fetchedTip <$> fetched

expectRight :: Either String a -> IO a
expectRight =
    \case
        Left err ->
            expectationFailure err *> fail err
        Right value ->
            pure value
