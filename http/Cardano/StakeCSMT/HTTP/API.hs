{- |
Module      : Cardano.StakeCSMT.HTTP.API
Description : Servant API and wire codecs for the stake CSMT service.
-}
module Cardano.StakeCSMT.HTTP.API
    ( API
    , api
    , StakeProofResponse (..)
    , StakeRootResponse (..)
    , HistoryRootResponse (..)
    , ReadyResponse (..)
    , MetricsResponse (..)
    , LatestHeaderResponse (..)
    , renderCredentialBase16
    , parseCredentialBase16
    , renderCoinBase16
    , parseCoinBase16
    , renderEpochNoBase16
    , parseEpochNoBase16
    , renderHashBase16
    , parseHashBase16
    , renderProofBase16
    ) where

import CSMT.Hashes
    ( Hash
    , renderHash
    )
import Cardano.Ledger.Coin
    ( Coin (Coin, unCoin)
    )
import Cardano.Ledger.Credential
    ( Credential
    )
import Cardano.Ledger.Keys
    ( KeyRole (Staking)
    )
import Cardano.Slotting.Slot
    ( EpochNo (EpochNo, unEpochNo)
    )
import Cardano.StakeCSMT.CSMT.Codecs
    ( coinCodec
    , credentialCodec
    , csmtHashCodec
    , epochNoCodec
    )
import Cardano.StakeCSMT.HTTP.Base16
    ( decodeBase16Text
    , encodeBase16Text
    )
import Control.Lens
    ( preview
    , review
    , (&)
    , (.~)
    , (?~)
    )
import Data.Aeson
    ( FromJSON (..)
    , ToJSON (..)
    , object
    , withObject
    , (.:)
    , (.=)
    )
import Data.ByteString
    ( ByteString
    )
import Data.Functor.Identity
    ( Identity
    )
import Data.Proxy
    ( Proxy (..)
    )
import Data.Swagger
    ( ToSchema (..)
    , declareSchemaRef
    , description
    , properties
    , required
    )
import Data.Swagger qualified as Swagger
import Data.Swagger.Declare
    ( DeclareT
    )
import Data.Text
    ( Text
    )
import Data.Word
    ( Word64
    )
import GHC.IsList
    ( IsList (..)
    )
import Servant
    ( Capture
    , Get
    , JSON
    , PlainText
    , type (:<|>)
    , type (:>)
    )

type API =
    "health" :> Get '[PlainText] Text
        :<|> "proof"
            :> Capture "credential" Text
            :> Get '[JSON] StakeProofResponse
        :<|> "proof"
            :> Capture "epoch" Word64
            :> Capture "credential" Text
            :> Get '[JSON] StakeProofResponse
        :<|> "roots"
            :> Get '[JSON] [StakeRootResponse]
        :<|> "history-root"
            :> Get '[JSON] HistoryRootResponse
        :<|> "ready"
            :> Get '[JSON] ReadyResponse
        :<|> "metrics"
            :> Get '[JSON] MetricsResponse

api :: Proxy API
api = Proxy

data StakeProofResponse = StakeProofResponse
    { epoch :: !EpochNo
    , credential :: !Text
    , stake :: !Coin
    , stakeRoot :: !Text
    , totalStake :: !Coin
    , proofBytes :: !Text
    }
    deriving stock (Eq, Show)

data StakeRootResponse = StakeRootResponse
    { epoch :: !EpochNo
    , stakeRoot :: !Text
    , totalStake :: !Coin
    }
    deriving stock (Eq, Show)

newtype HistoryRootResponse = HistoryRootResponse
    { historyRoot :: Text
    }
    deriving stock (Eq, Show)

newtype ReadyResponse = ReadyResponse
    { ready :: Bool
    }
    deriving stock (Eq, Show)

data MetricsResponse = MetricsResponse
    { ready :: !Bool
    , latestEpoch :: !(Maybe EpochNo)
    }
    deriving stock (Eq, Show)

data LatestHeaderResponse = LatestHeaderResponse
    { epoch :: !EpochNo
    , stakeRoot :: !Text
    , totalStake :: !Coin
    }
    deriving stock (Eq, Show)

instance ToJSON StakeProofResponse where
    toJSON
        StakeProofResponse
            { epoch
            , credential
            , stake
            , stakeRoot
            , totalStake
            , proofBytes
            } =
            object
                [ "epoch" .= epochToWord64 epoch
                , "credential" .= credential
                , "stake" .= coinToInteger stake
                , "stakeRoot" .= stakeRoot
                , "totalStake" .= coinToInteger totalStake
                , "proofBytes" .= proofBytes
                ]

instance FromJSON StakeProofResponse where
    parseJSON = withObject "StakeProofResponse" $ \obj ->
        (StakeProofResponse . word64ToEpoch <$> (obj .: "epoch"))
            <*> obj .: "credential"
            <*> (Coin <$> obj .: "stake")
            <*> obj .: "stakeRoot"
            <*> (Coin <$> obj .: "totalStake")
            <*> obj .: "proofBytes"

instance ToSchema StakeProofResponse where
    declareNamedSchema _ =
        objectSchema
            "StakeProofResponse"
            [ SchemaField "epoch" (Proxy @Word64)
            , SchemaField "credential" (Proxy @String)
            , SchemaField "stake" (Proxy @Integer)
            , SchemaField "stakeRoot" (Proxy @String)
            , SchemaField "totalStake" (Proxy @Integer)
            , SchemaField "proofBytes" (Proxy @String)
            ]
            "Stake inclusion proof encoded for the HTTP API."

instance ToJSON StakeRootResponse where
    toJSON StakeRootResponse{epoch, stakeRoot, totalStake} =
        object
            [ "epoch" .= epochToWord64 epoch
            , "stakeRoot" .= stakeRoot
            , "totalStake" .= coinToInteger totalStake
            ]

instance FromJSON StakeRootResponse where
    parseJSON = withObject "StakeRootResponse" $ \obj ->
        (StakeRootResponse . word64ToEpoch <$> (obj .: "epoch"))
            <*> obj .: "stakeRoot"
            <*> (Coin <$> obj .: "totalStake")

instance ToSchema StakeRootResponse where
    declareNamedSchema _ =
        objectSchema
            "StakeRootResponse"
            [ SchemaField "epoch" (Proxy @Word64)
            , SchemaField "stakeRoot" (Proxy @String)
            , SchemaField "totalStake" (Proxy @Integer)
            ]
            "Stake CSMT root for one epoch."

instance ToJSON HistoryRootResponse where
    toJSON HistoryRootResponse{historyRoot} =
        object
            [ "historyRoot" .= historyRoot
            ]

instance FromJSON HistoryRootResponse where
    parseJSON = withObject "HistoryRootResponse" $ \obj ->
        HistoryRootResponse <$> obj .: "historyRoot"

instance ToSchema HistoryRootResponse where
    declareNamedSchema _ =
        objectSchema
            "HistoryRootResponse"
            [ SchemaField "historyRoot" (Proxy @String)
            ]
            "History tree root that commits to stake roots."

instance ToJSON ReadyResponse where
    toJSON ReadyResponse{ready} =
        object ["ready" .= ready]

instance FromJSON ReadyResponse where
    parseJSON = withObject "ReadyResponse" $ \obj ->
        ReadyResponse <$> obj .: "ready"

instance ToSchema ReadyResponse where
    declareNamedSchema _ =
        objectSchema
            "ReadyResponse"
            [ SchemaField "ready" (Proxy @Bool)
            ]
            "Readiness status for orchestration."

instance ToJSON MetricsResponse where
    toJSON MetricsResponse{ready, latestEpoch} =
        object
            [ "ready" .= ready
            , "latestEpoch" .= fmap epochToWord64 latestEpoch
            ]

instance FromJSON MetricsResponse where
    parseJSON = withObject "MetricsResponse" $ \obj ->
        MetricsResponse
            <$> obj .: "ready"
            <*> (fmap word64ToEpoch <$> obj .: "latestEpoch")

instance ToSchema MetricsResponse where
    declareNamedSchema _ =
        objectSchema
            "MetricsResponse"
            [ SchemaField "ready" (Proxy @Bool)
            , SchemaField "latestEpoch" (Proxy @(Maybe Word64))
            ]
            "Minimal HTTP metrics for the stake service."

instance ToJSON LatestHeaderResponse where
    toJSON LatestHeaderResponse{epoch, stakeRoot, totalStake} =
        object
            [ "epoch" .= epochToWord64 epoch
            , "stakeRoot" .= stakeRoot
            , "totalStake" .= coinToInteger totalStake
            ]

instance FromJSON LatestHeaderResponse where
    parseJSON = withObject "LatestHeaderResponse" $ \obj ->
        (LatestHeaderResponse . word64ToEpoch <$> (obj .: "epoch"))
            <*> obj .: "stakeRoot"
            <*> (Coin <$> obj .: "totalStake")

instance ToSchema LatestHeaderResponse where
    declareNamedSchema _ =
        objectSchema
            "LatestHeaderResponse"
            [ SchemaField "epoch" (Proxy @Word64)
            , SchemaField "stakeRoot" (Proxy @String)
            , SchemaField "totalStake" (Proxy @Integer)
            ]
            "Latest stake root header."

renderCredentialBase16 :: Credential Staking -> Text
renderCredentialBase16 =
    encodeBase16Text . review credentialCodec

parseCredentialBase16 :: Text -> Either String (Credential Staking)
parseCredentialBase16 text = do
    bytes <- decodeBase16Text text
    maybe (Left "invalid credential CBOR") Right
        $ preview credentialCodec bytes

renderCoinBase16 :: Coin -> Text
renderCoinBase16 =
    encodeBase16Text . review coinCodec

parseCoinBase16 :: Text -> Either String Coin
parseCoinBase16 text = do
    bytes <- decodeBase16Text text
    maybe (Left "invalid coin CBOR") Right $ preview coinCodec bytes

renderEpochNoBase16 :: EpochNo -> Text
renderEpochNoBase16 =
    encodeBase16Text . review epochNoCodec

parseEpochNoBase16 :: Text -> Either String EpochNo
parseEpochNoBase16 text = do
    bytes <- decodeBase16Text text
    maybe (Left "invalid epoch CBOR") Right $ preview epochNoCodec bytes

renderHashBase16 :: Hash -> Text
renderHashBase16 =
    encodeBase16Text . renderHash

parseHashBase16 :: Text -> Either String Hash
parseHashBase16 text = do
    bytes <- decodeBase16Text text
    maybe (Left "invalid CSMT hash") Right $ preview csmtHashCodec bytes

renderProofBase16 :: ByteString -> Text
renderProofBase16 =
    encodeBase16Text

coinToInteger :: Coin -> Integer
coinToInteger =
    unCoin

epochToWord64 :: EpochNo -> Word64
epochToWord64 =
    unEpochNo

word64ToEpoch :: Word64 -> EpochNo
word64ToEpoch =
    EpochNo

data SchemaField where
    SchemaField :: (ToSchema a) => Text -> Proxy a -> SchemaField

objectSchema
    :: Text
    -> [SchemaField]
    -> Text
    -> DeclareT
        (Swagger.Definitions Swagger.Schema)
        Identity
        Swagger.NamedSchema
objectSchema name fields schemaDescription = do
    declaredProperties <- traverse declareProperty fields
    pure
        $ Swagger.NamedSchema (Just name)
        $ mempty
        & Swagger.type_ ?~ Swagger.SwaggerObject
        & properties .~ fromList declaredProperties
        & required .~ fmap schemaFieldName fields
        & description ?~ schemaDescription
  where
    schemaFieldName :: SchemaField -> Text
    schemaFieldName (SchemaField fieldName _) =
        fieldName

    declareProperty (SchemaField fieldName proxy) =
        (fieldName,) <$> declareSchemaRef proxy
