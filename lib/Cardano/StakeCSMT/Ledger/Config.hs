module Cardano.StakeCSMT.Ledger.Config
    ( CardanoBlock
    , LedgerConfigBundle (..)
    , LedgerConfigPaths (..)
    , StakeBlock
    , ledgerConfigEpochAt
    , ledgerConfigPathsFromDirectory
    , loadLedgerConfig
    )
where

import Cardano.Chain.Genesis qualified as ByronGenesis
import Cardano.Chain.Slotting
    ( EpochSlots (..)
    )
import Cardano.Chain.UTxO qualified as ByronUTxO
import Cardano.Chain.Update qualified as ByronUpdate
import Cardano.Crypto.Hash qualified as ByronHash
import Cardano.Crypto.Hash.Class qualified as Crypto
import Cardano.Crypto.Hashing qualified as ByronHashing
import Cardano.Crypto.ProtocolMagic
    ( RequiresNetworkMagic (RequiresNoMagic)
    )
import Cardano.Ledger.Alonzo.Genesis
    ( AlonzoGenesis
    )
import Cardano.Ledger.Api.Transition qualified as LedgerTransition
import Cardano.Ledger.BaseTypes
    ( ProtVer (..)
    , boundRational
    , natVersion
    , unsafeNonZero
    )
import Cardano.Ledger.Conway.Genesis
    ( ConwayGenesis
    )
import Cardano.Ledger.Dijkstra.PParams
    ( UpgradeDijkstraPParams (..)
    )
import Cardano.Ledger.Shelley.Genesis
    ( ShelleyGenesis
    )
import Cardano.Node.Types
    ( GenesisHash (..)
    )
import Cardano.Slotting.EpochInfo.API
    ( EpochInfo
    , epochInfoEpoch
    )
import Cardano.Slotting.Slot
    ( EpochNo (..)
    , SlotNo (..)
    )
import Control.Applicative
    ( (<|>)
    )
import Control.Exception
    ( throwIO
    )
import Control.Monad
    ( unless
    )
import Control.Monad.Except
    ( runExceptT
    )
import Control.Monad.Trans.Except
    ( Except
    , runExcept
    )
import Data.Aeson
    ( FromJSON (..)
    , Value (..)
    , withObject
    , (.:?)
    )
import Data.Aeson qualified as Aeson
import Data.Aeson.KeyMap qualified as KeyMap
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.Maybe
    ( fromMaybe
    )
import Data.Word
    ( Word16
    , Word64
    , Word8
    )
import Ouroboros.Consensus.Byron.Node
    ( ProtocolParamsByron (..)
    )
import Ouroboros.Consensus.Cardano
    ( CardanoHardForkTrigger (..)
    , CardanoHardForkTriggers (..)
    , ProtocolParamsShelleyBased (..)
    )
import Ouroboros.Consensus.Cardano.Block
    ( CardanoBlock
    , CardanoEras
    )
import Ouroboros.Consensus.Cardano.Node
    ( CardanoProtocolParams (..)
    , protocolInfoCardano
    )
import Ouroboros.Consensus.Config
    ( TopLevelConfig
    , configLedger
    , emptyCheckpointsMap
    )
import Ouroboros.Consensus.HardFork.Abstract
    ( hardForkSummary
    )
import Ouroboros.Consensus.HardFork.History.EpochInfo
    ( interpreterToEpochInfo
    )
import Ouroboros.Consensus.HardFork.History.Qry
    ( Interpreter
    , PastHorizonException
    )
import Ouroboros.Consensus.HardFork.History.Qry qualified as History
import Ouroboros.Consensus.Ledger.Basics
    ( LedgerConfig
    , ValuesMK
    )
import Ouroboros.Consensus.Ledger.Extended
    ( ExtLedgerState (..)
    )
import Ouroboros.Consensus.Node.ProtocolInfo
    ( ProtocolInfo (..)
    )
import Ouroboros.Consensus.Protocol.PBFT
    ( PBftSignatureThreshold (..)
    )
import Ouroboros.Consensus.Shelley.Crypto
    ( StandardCrypto
    )
import Ouroboros.Consensus.Shelley.Ledger.SupportsProtocol ()
import Ouroboros.Consensus.Shelley.Node
    ( Nonce (..)
    )
import System.FilePath
    ( (</>)
    )

type StakeBlock = CardanoBlock StandardCrypto

data LedgerConfigPaths = LedgerConfigPaths
    { ledgerConfigNodeConfigFile :: !FilePath
    , ledgerConfigByronGenesisFile :: !FilePath
    , ledgerConfigShelleyGenesisFile :: !FilePath
    , ledgerConfigAlonzoGenesisFile :: !FilePath
    , ledgerConfigConwayGenesisFile :: !FilePath
    }
    deriving stock (Eq, Show)

data LedgerConfigBundle = LedgerConfigBundle
    { ledgerConfigProtocolInfo :: !(ProtocolInfo StakeBlock)
    , ledgerConfigGenesisState :: !(ExtLedgerState StakeBlock ValuesMK)
    , ledgerConfigLedgerConfig :: !(LedgerConfig StakeBlock)
    , ledgerConfigTopLevelConfig :: !(TopLevelConfig StakeBlock)
    , ledgerConfigEraHistory :: !(Interpreter (CardanoEras StandardCrypto))
    , ledgerConfigEpochInfo :: !(EpochInfo (Except PastHorizonException))
    , ledgerConfigByronEpochSlots :: !Word64
    }

ledgerConfigPathsFromDirectory :: FilePath -> LedgerConfigPaths
ledgerConfigPathsFromDirectory directory =
    LedgerConfigPaths
        { ledgerConfigNodeConfigFile = directory </> "node-config.json"
        , ledgerConfigByronGenesisFile = directory </> "byron-genesis.json"
        , ledgerConfigShelleyGenesisFile = directory </> "shelley-genesis.json"
        , ledgerConfigAlonzoGenesisFile = directory </> "alonzo-genesis.json"
        , ledgerConfigConwayGenesisFile = directory </> "conway-genesis.json"
        }

loadLedgerConfig :: LedgerConfigPaths -> IO LedgerConfigBundle
loadLedgerConfig paths = do
    nodeConfig <-
        readJsonFile "node config" (ledgerConfigNodeConfigFile paths)
    (protocolParams, byronEpochSlots) <-
        loadProtocolParams paths nodeConfig
    let protocolInfo = fst $ protocolInfoCardano @StandardCrypto @IO protocolParams
        topLevelConfig = pInfoConfig protocolInfo
        genesisState = pInfoInitLedger protocolInfo
        ledgerConfig = configLedger topLevelConfig
        eraHistory =
            History.mkInterpreter
                $ hardForkSummary ledgerConfig (ledgerState genesisState)
        epochInfo = interpreterToEpochInfo eraHistory
    pure
        LedgerConfigBundle
            { ledgerConfigProtocolInfo = protocolInfo
            , ledgerConfigGenesisState = genesisState
            , ledgerConfigLedgerConfig = ledgerConfig
            , ledgerConfigTopLevelConfig = topLevelConfig
            , ledgerConfigEraHistory = eraHistory
            , ledgerConfigEpochInfo = epochInfo
            , ledgerConfigByronEpochSlots = byronEpochSlots
            }

ledgerConfigEpochAt :: LedgerConfigBundle -> Word64 -> IO Word64
ledgerConfigEpochAt LedgerConfigBundle{ledgerConfigEpochInfo} slot =
    case runExcept $ epochInfoEpoch ledgerConfigEpochInfo (SlotNo slot) of
        Left pastHorizon ->
            throwIO pastHorizon
        Right (EpochNo epoch) ->
            pure epoch

data NodeConfig = NodeConfig
    { ncByronGenesisHash :: !(Maybe GenesisHash)
    , ncShelleyGenesisHash :: !(Maybe GenesisHash)
    , ncAlonzoGenesisHash :: !(Maybe GenesisHash)
    , ncConwayGenesisHash :: !(Maybe GenesisHash)
    , ncRequiresNetworkMagic :: !RequiresNetworkMagic
    , ncPbftSignatureThreshold :: !(Maybe Double)
    , ncLastKnownBlockVersionMajor :: !Word16
    , ncLastKnownBlockVersionMinor :: !Word16
    , ncLastKnownBlockVersionAlt :: !Word8
    , ncExperimentalHardForksEnabled :: !Bool
    , ncTestShelleyHardForkAtEpoch :: !(Maybe EpochNo)
    , ncTestAllegraHardForkAtEpoch :: !(Maybe EpochNo)
    , ncTestMaryHardForkAtEpoch :: !(Maybe EpochNo)
    , ncTestAlonzoHardForkAtEpoch :: !(Maybe EpochNo)
    , ncTestBabbageHardForkAtEpoch :: !(Maybe EpochNo)
    , ncTestConwayHardForkAtEpoch :: !(Maybe EpochNo)
    , ncTestDijkstraHardForkAtEpoch :: !(Maybe EpochNo)
    }

instance FromJSON NodeConfig where
    parseJSON =
        withObject "NodeConfig" $ \object -> do
            experimentalHardForksEnabled <-
                fromMaybe False
                    <$> ( object .:? "ExperimentalHardForksEnabled"
                            <|> object .:? "TestEnableDevelopmentHardForkEras"
                        )
            NodeConfig
                <$> object .:? "ByronGenesisHash"
                <*> object .:? "ShelleyGenesisHash"
                <*> object .:? "AlonzoGenesisHash"
                <*> object .:? "ConwayGenesisHash"
                <*> (fromMaybe RequiresNoMagic <$> object .:? "RequiresNetworkMagic")
                <*> object .:? "PBftSignatureThreshold"
                <*> (fromMaybe 0 <$> object .:? "LastKnownBlockVersion-Major")
                <*> (fromMaybe 0 <$> object .:? "LastKnownBlockVersion-Minor")
                <*> (fromMaybe 0 <$> object .:? "LastKnownBlockVersion-Alt")
                <*> pure experimentalHardForksEnabled
                <*> hardForkEpoch
                    experimentalHardForksEnabled
                    object
                    "TestShelleyHardForkAtEpoch"
                <*> hardForkEpoch
                    experimentalHardForksEnabled
                    object
                    "TestAllegraHardForkAtEpoch"
                <*> hardForkEpoch
                    experimentalHardForksEnabled
                    object
                    "TestMaryHardForkAtEpoch"
                <*> hardForkEpoch
                    experimentalHardForksEnabled
                    object
                    "TestAlonzoHardForkAtEpoch"
                <*> hardForkEpoch
                    experimentalHardForksEnabled
                    object
                    "TestBabbageHardForkAtEpoch"
                <*> hardForkEpoch
                    experimentalHardForksEnabled
                    object
                    "TestConwayHardForkAtEpoch"
                <*> hardForkEpoch
                    experimentalHardForksEnabled
                    object
                    "TestDijkstraHardForkAtEpoch"
      where
        hardForkEpoch enabled object key =
            if enabled
                then object .:? key
                else pure Nothing

loadProtocolParams
    :: LedgerConfigPaths
    -> NodeConfig
    -> IO (CardanoProtocolParams StandardCrypto, Word64)
loadProtocolParams paths NodeConfig{..} = do
    byronGenesis <-
        readByronGenesis
            (ledgerConfigByronGenesisFile paths)
            ncByronGenesisHash
            ncRequiresNetworkMagic
    (shelleyGenesis, shelleyGenesisHash) <-
        readShelleyGenesis
            (ledgerConfigShelleyGenesisFile paths)
            ncShelleyGenesisHash
    (alonzoGenesis :: AlonzoGenesis, _) <-
        readGenesisAny
            "Alonzo genesis"
            (ledgerConfigAlonzoGenesisFile paths)
            ncAlonzoGenesisHash
    (conwayGenesis :: ConwayGenesis, _) <-
        readGenesisAny
            "Conway genesis"
            (ledgerConfigConwayGenesisFile paths)
            ncConwayGenesisHash
    let ledgerTransitionConfig =
            LedgerTransition.mkLatestTransitionConfig
                shelleyGenesis
                alonzoGenesis
                conwayGenesis
                emptyDijkstraGenesis
    let EpochSlots byronEpochSlots =
            ByronGenesis.configEpochSlots byronGenesis
    pure
        ( CardanoProtocolParams
            { byronProtocolParams =
                ProtocolParamsByron
                    { byronGenesis = byronGenesis
                    , byronPbftSignatureThreshold =
                        PBftSignatureThreshold <$> ncPbftSignatureThreshold
                    , byronProtocolVersion =
                        ByronUpdate.ProtocolVersion
                            ncLastKnownBlockVersionMajor
                            ncLastKnownBlockVersionMinor
                            ncLastKnownBlockVersionAlt
                    , byronSoftwareVersion =
                        ByronUpdate.SoftwareVersion
                            (ByronUpdate.ApplicationName "cardano-stake-csmt")
                            0
                    , byronLeaderCredentials = Nothing
                    }
            , shelleyBasedProtocolParams =
                ProtocolParamsShelleyBased
                    { shelleyBasedInitialNonce =
                        genesisHashToPraosNonce shelleyGenesisHash
                    , shelleyBasedLeaderCredentials = []
                    }
            , cardanoHardForkTriggers =
                CardanoHardForkTriggers'
                    { triggerHardForkShelley =
                        hardForkTrigger ncTestShelleyHardForkAtEpoch
                    , triggerHardForkAllegra =
                        hardForkTrigger ncTestAllegraHardForkAtEpoch
                    , triggerHardForkMary =
                        hardForkTrigger ncTestMaryHardForkAtEpoch
                    , triggerHardForkAlonzo =
                        hardForkTrigger ncTestAlonzoHardForkAtEpoch
                    , triggerHardForkBabbage =
                        hardForkTrigger ncTestBabbageHardForkAtEpoch
                    , triggerHardForkConway =
                        hardForkTrigger ncTestConwayHardForkAtEpoch
                    , triggerHardForkDijkstra =
                        hardForkTrigger ncTestDijkstraHardForkAtEpoch
                    }
            , cardanoLedgerTransitionConfig = ledgerTransitionConfig
            , cardanoCheckpoints = emptyCheckpointsMap
            , cardanoProtocolVersion =
                if ncExperimentalHardForksEnabled
                    then ProtVer (natVersion @11) 0
                    else ProtVer (natVersion @10) 7
            }
        , byronEpochSlots
        )
hardForkTrigger :: Maybe EpochNo -> CardanoHardForkTrigger block
hardForkTrigger =
    maybe
        CardanoTriggerHardForkAtDefaultVersion
        CardanoTriggerHardForkAtEpoch

readJsonFile :: FromJSON a => String -> FilePath -> IO a
readJsonFile label file = do
    content <- BS.readFile file
    case Aeson.eitherDecodeStrict' content of
        Left decodeError ->
            fail $ label <> " decode failed at " <> file <> ": " <> decodeError
        Right value ->
            pure value

readByronGenesis
    :: FilePath
    -> Maybe GenesisHash
    -> RequiresNetworkMagic
    -> IO ByronGenesis.Config
readByronGenesis file expectedHash requiresNetworkMagic = do
    (genesisData, actualHash) <-
        runExceptT (ByronGenesis.readGenesisData file)
            >>= either
                ( \err ->
                    fail
                        $ "Byron genesis decode failed at "
                            <> file
                            <> ": "
                            <> show err
                )
                pure
    checkExpectedGenesisHash
        "Byron genesis"
        file
        expectedHash
        (fromByronGenesisHash actualHash)
    pure
        ByronGenesis.Config
            { ByronGenesis.configGenesisData = genesisData
            , ByronGenesis.configGenesisHash = actualHash
            , ByronGenesis.configReqNetMagic = requiresNetworkMagic
            , ByronGenesis.configUTxOConfiguration =
                ByronUTxO.defaultUTxOConfiguration
            }

readShelleyGenesis
    :: FilePath -> Maybe GenesisHash -> IO (ShelleyGenesis, GenesisHash)
readShelleyGenesis =
    readGenesisAnyWith normaliseShelleyGenesisContent "Shelley genesis"

readGenesisAny
    :: FromJSON genesis
    => String
    -> FilePath
    -> Maybe GenesisHash
    -> IO (genesis, GenesisHash)
readGenesisAny =
    readGenesisAnyWith id

readGenesisAnyWith
    :: FromJSON genesis
    => (BS.ByteString -> BS.ByteString)
    -> String
    -> FilePath
    -> Maybe GenesisHash
    -> IO (genesis, GenesisHash)
readGenesisAnyWith adjustContent label file expectedHash = do
    content <- adjustContent <$> BS.readFile file
    let actualHash = GenesisHash $ Crypto.hashWith id content
    checkExpectedGenesisHash label file expectedHash actualHash
    case Aeson.eitherDecodeStrict' content of
        Left decodeError ->
            fail $ label <> " decode failed at " <> file <> ": " <> decodeError
        Right genesis ->
            pure (genesis, actualHash)

normaliseShelleyGenesisContent :: BS.ByteString -> BS.ByteString
normaliseShelleyGenesisContent content =
    case Aeson.decodeStrict' content of
        Just (Object object)
            | Just (String "PLACEHOLDER") <- "systemStart" `lookupObject` object ->
                LBS.toStrict
                    $ Aeson.encode
                    $ Object
                    $ insertObject
                        "systemStart"
                        (String "1970-01-01T00:00:00Z")
                        object
        _ ->
            content
  where
    lookupObject = KeyMap.lookup
    insertObject = KeyMap.insert

checkExpectedGenesisHash
    :: String
    -> FilePath
    -> Maybe GenesisHash
    -> GenesisHash
    -> IO ()
checkExpectedGenesisHash _label _file Nothing _actual =
    pure ()
checkExpectedGenesisHash label file (Just expected) actual =
    unless (expected == actual)
        $ fail
        $ label
            <> " hash mismatch at "
            <> file
            <> ": expected "
            <> show expected
            <> ", got "
            <> show actual

fromByronGenesisHash :: ByronGenesis.GenesisHash -> GenesisHash
fromByronGenesisHash (ByronGenesis.GenesisHash hash) =
    GenesisHash
        . fromMaybe impossible
        . ByronHash.hashFromBytes
        . ByronHashing.hashToBytes
        $ hash
  where
    impossible =
        error
            "fromByronGenesisHash: old and new crypto libraries disagree on hash size"

genesisHashToPraosNonce :: GenesisHash -> Nonce
genesisHashToPraosNonce (GenesisHash hash) =
    Nonce (Crypto.castHash hash)

emptyDijkstraGenesis :: LedgerTransition.DijkstraGenesis
emptyDijkstraGenesis =
    LedgerTransition.DijkstraGenesis
        { LedgerTransition.dgUpgradePParams =
            UpgradeDijkstraPParams
                { udppMaxRefScriptSizePerBlock = 1_048_576
                , udppMaxRefScriptSizePerTx = 204_800
                , udppRefScriptCostStride = unsafeNonZero 25_600
                , udppRefScriptCostMultiplier =
                    fromMaybe
                        (error "emptyDijkstraGenesis: invalid cost multiplier")
                        $ boundRational 1.2
                }
        }
