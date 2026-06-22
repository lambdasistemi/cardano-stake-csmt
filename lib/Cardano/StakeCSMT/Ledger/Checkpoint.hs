{- |
Module      : Cardano.StakeCSMT.Ledger.Checkpoint
Description : Finalized-boundary checkpoints and replay-tail helpers.

Persist finalized-boundary metadata and keep a bounded volatile tail of fetched
blocks so later replay integration can re-derive near-tip state without
serializing full ledger state.
-}
module Cardano.StakeCSMT.Ledger.Checkpoint
    ( CheckpointPoint (..)
    , ReplayCheckpoint (..)
    , ReplayTail
    , appendReplayTail
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
    ) where

import Cardano.Node.Client.N2C.ChainSync
    ( Fetched (..)
    , HeaderPoint
    )
import Codec.CBOR.Decoding qualified as CBOR.Decoding
import Codec.CBOR.Encoding qualified as CBOR.Encoding
import Codec.CBOR.Read qualified as CBOR.Read
import Codec.CBOR.Write qualified as CBOR.Write
import Data.ByteString.Lazy qualified as LBS
import Data.List
    ( isSuffixOf
    , sort
    , stripPrefix
    )
import Data.Maybe
    ( mapMaybe
    )
import Data.Word
    ( Word64
    )
import Ouroboros.Network.Block qualified as Network
import Ouroboros.Network.Point qualified as Network.Point
import System.Directory
    ( createDirectoryIfMissing
    , doesDirectoryExist
    , doesFileExist
    , listDirectory
    )
import System.FilePath
    ( (</>)
    )
import Text.Read
    ( readMaybe
    )

-- | Comparable location used for checkpoint selection and tail slicing.
data CheckpointPoint
    = CheckpointOrigin
    | CheckpointAtBlock !Word64
    deriving stock (Eq, Ord, Show)

-- | Persisted metadata for an immutable finalized replay boundary.
data ReplayCheckpoint = ReplayCheckpoint
    { replayCheckpointPoint :: !CheckpointPoint
    , replayCheckpointFinalizedEpoch :: !Word64
    , replayCheckpointObservedEpoch :: !Word64
    }
    deriving stock (Eq, Show)

-- | Bounded fetched-block tail, stored oldest to newest.
newtype ReplayTail = ReplayTail
    { replayTailEntries :: [ReplayTailEntry]
    }

data ReplayTailEntry = ReplayTailEntry
    { replayTailEntryPoint :: !CheckpointPoint
    , replayTailEntryFetched :: Fetched
    }

-- | Empty replay tail.
emptyReplayTail :: ReplayTail
emptyReplayTail =
    ReplayTail []

-- | Append a fetched block at its chain point.
appendReplayTail :: Int -> Fetched -> ReplayTail -> ReplayTail
appendReplayTail limit fetched =
    appendReplayTailAt limit (fetchedCheckpointPoint fetched) fetched

{- | Append a fetched block at an explicit point.

This is useful for recovery code that already normalized a chain point and for
tests that should not construct full Cardano header points.
-}
appendReplayTailAt
    :: Int
    -> CheckpointPoint
    -> Fetched
    -> ReplayTail
    -> ReplayTail
appendReplayTailAt limit point fetched ReplayTail{replayTailEntries} =
    ReplayTail
        $ keepNewest limit
        $ replayTailEntries
            <> [ ReplayTailEntry
                    { replayTailEntryPoint = point
                    , replayTailEntryFetched = fetched
                    }
               ]

-- | Return retained fetched blocks oldest to newest.
replayTailFetched :: ReplayTail -> [Fetched]
replayTailFetched ReplayTail{replayTailEntries} =
    replayTailEntryFetched <$> replayTailEntries

-- | Drop retained blocks after a rollback target.
truncateReplayTailAfter :: CheckpointPoint -> ReplayTail -> ReplayTail
truncateReplayTailAfter target ReplayTail{replayTailEntries} =
    ReplayTail
        $ takeWhile ((<= target) . replayTailEntryPoint) replayTailEntries

{- | Return the retained blocks required to replay from a finalized boundary to
a rollback target.

The helper fails when the boundary is after the target or when any retained
block needed after the boundary is missing from the current bounded tail.
-}
recoverReplayTail
    :: CheckpointPoint
    -> CheckpointPoint
    -> ReplayTail
    -> Maybe [Fetched]
recoverReplayTail boundary target ReplayTail{replayTailEntries}
    | target < boundary =
        Nothing
    | otherwise =
        let required =
                takeWhile
                    ((<= target) . replayTailEntryPoint)
                    $ dropWhile
                        ((<= boundary) . replayTailEntryPoint)
                        replayTailEntries
        in  if replayTailCovers boundary required target
                then Just $ replayTailEntryFetched <$> required
                else Nothing

-- | Convert a chain-sync point into checkpoint ordering metadata.
checkpointPointFromHeaderPoint :: HeaderPoint -> CheckpointPoint
checkpointPointFromHeaderPoint point =
    case Network.pointSlot point of
        Network.Point.Origin ->
            CheckpointOrigin
        Network.Point.At (Network.SlotNo slot) ->
            CheckpointAtBlock slot

-- | Encode finalized-boundary checkpoint metadata.
encodeReplayCheckpoint :: ReplayCheckpoint -> LBS.ByteString
encodeReplayCheckpoint
    ReplayCheckpoint
        { replayCheckpointPoint
        , replayCheckpointFinalizedEpoch
        , replayCheckpointObservedEpoch
        } =
        CBOR.Write.toLazyByteString
            $ CBOR.Encoding.encodeListLen 3
                <> encodeCheckpointPoint replayCheckpointPoint
                <> CBOR.Encoding.encodeWord64 replayCheckpointFinalizedEpoch
                <> CBOR.Encoding.encodeWord64 replayCheckpointObservedEpoch

-- | Decode checkpoint metadata previously written by 'encodeReplayCheckpoint'.
decodeReplayCheckpoint
    :: LBS.ByteString -> Either String ReplayCheckpoint
decodeReplayCheckpoint bytes =
    case CBOR.Read.deserialiseFromBytes decodeReplayCheckpointDecoder bytes of
        Left failure ->
            Left $ show failure
        Right (trailing, checkpoint)
            | LBS.null trailing ->
                Right checkpoint
            | otherwise ->
                Left "checkpoint decoder left trailing bytes"

-- | Save a checkpoint under its deterministic point-derived filename.
saveReplayCheckpoint :: FilePath -> ReplayCheckpoint -> IO FilePath
saveReplayCheckpoint directory checkpoint = do
    createDirectoryIfMissing True directory
    let path =
            replayCheckpointPath directory $ replayCheckpointPoint checkpoint
    LBS.writeFile path $ encodeReplayCheckpoint checkpoint
    pure path

-- | Load one checkpoint by point.
loadReplayCheckpoint
    :: FilePath
    -> CheckpointPoint
    -> IO (Either String ReplayCheckpoint)
loadReplayCheckpoint directory point = do
    let path = replayCheckpointPath directory point
    exists <- doesFileExist path
    if exists
        then decodeReplayCheckpoint <$> LBS.readFile path
        else pure $ Left $ "checkpoint not found: " <> path

-- | List checkpoint points present in a directory.
listReplayCheckpoints :: FilePath -> IO [CheckpointPoint]
listReplayCheckpoints directory = do
    exists <- doesDirectoryExist directory
    if exists
        then
            sort . mapMaybe checkpointPointFromFileName
                <$> listDirectory directory
        else pure []

-- | Select the newest checkpoint at or before a target point.
nearestCheckpointAtOrBefore
    :: [CheckpointPoint]
    -> CheckpointPoint
    -> Maybe CheckpointPoint
nearestCheckpointAtOrBefore points target =
    case filter (<= target) $ sort points of
        [] ->
            Nothing
        candidates ->
            Just $ last candidates

decodeReplayCheckpointDecoder
    :: CBOR.Decoding.Decoder s ReplayCheckpoint
decodeReplayCheckpointDecoder = do
    CBOR.Decoding.decodeListLenOf 3
    replayCheckpointPoint <- decodeCheckpointPoint
    replayCheckpointFinalizedEpoch <- CBOR.Decoding.decodeWord64
    replayCheckpointObservedEpoch <- CBOR.Decoding.decodeWord64
    pure
        ReplayCheckpoint
            { replayCheckpointPoint
            , replayCheckpointFinalizedEpoch
            , replayCheckpointObservedEpoch
            }

encodeCheckpointPoint :: CheckpointPoint -> CBOR.Encoding.Encoding
encodeCheckpointPoint point =
    case point of
        CheckpointOrigin ->
            CBOR.Encoding.encodeListLen 1
                <> CBOR.Encoding.encodeWord 0
        CheckpointAtBlock slot ->
            CBOR.Encoding.encodeListLen 2
                <> CBOR.Encoding.encodeWord 1
                <> CBOR.Encoding.encodeWord64 slot

decodeCheckpointPoint :: CBOR.Decoding.Decoder s CheckpointPoint
decodeCheckpointPoint = do
    len <- CBOR.Decoding.decodeListLen
    tag <- CBOR.Decoding.decodeWord
    case (len, tag) of
        (1, 0) ->
            pure CheckpointOrigin
        (2, 1) ->
            CheckpointAtBlock <$> CBOR.Decoding.decodeWord64
        _ ->
            fail "invalid checkpoint point"

replayCheckpointPath :: FilePath -> CheckpointPoint -> FilePath
replayCheckpointPath directory point =
    directory </> checkpointFileName point

checkpointFileName :: CheckpointPoint -> FilePath
checkpointFileName point =
    case point of
        CheckpointOrigin ->
            "checkpoint-origin.cbor"
        CheckpointAtBlock slot ->
            "checkpoint-slot-" <> show slot <> ".cbor"

checkpointPointFromFileName :: FilePath -> Maybe CheckpointPoint
checkpointPointFromFileName fileName =
    case fileName of
        "checkpoint-origin.cbor" ->
            Just CheckpointOrigin
        _ -> do
            slotText <-
                stripPrefix "checkpoint-slot-" fileName
                    >>= stripCheckpointSuffix
            CheckpointAtBlock <$> readMaybe slotText

fetchedCheckpointPoint :: Fetched -> CheckpointPoint
fetchedCheckpointPoint =
    checkpointPointFromHeaderPoint . fetchedPoint

replayTailCovers
    :: CheckpointPoint
    -> [ReplayTailEntry]
    -> CheckpointPoint
    -> Bool
replayTailCovers boundary required target =
    target == boundary
        || case required of
            [] ->
                False
            entries ->
                replayTailEntryPoint (last entries) == target

keepNewest :: Int -> [a] -> [a]
keepNewest limit entries =
    drop (length entries - max 0 limit) entries

stripCheckpointSuffix :: FilePath -> Maybe FilePath
stripCheckpointSuffix fileName
    | suffix `isSuffixOf` fileName =
        Just $ take (length fileName - length suffix) fileName
    | otherwise =
        Nothing
  where
    suffix = ".cbor"
