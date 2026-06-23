module Cardano.StakeCSMT.E2E.LiveHTTPSpec
    ( spec
    ) where

import CSMT.Hashes.CBOR
    ( parseProof
    )
import Cardano.Crypto.DSIGN.Class
    ( SignKeyDSIGN
    , genKeyDSIGN
    )
import Cardano.Crypto.DSIGN.Ed25519
    ( Ed25519DSIGN
    )
import Cardano.Crypto.Seed
    ( mkSeedFromBytes
    )
import Cardano.Node.Client.E2E.Devnet
    ( withCardanoNode
    )
import Cardano.Slotting.Slot
    ( EpochNo
    )
import Cardano.StakeCSMT.Application.Run.Config
    ( RuntimeConfig (..)
    )
import Cardano.StakeCSMT.Application.Run.Main qualified as Runtime
import Cardano.StakeCSMT.CSMT.Builder
    ( verifyCredentialProof
    )
import Cardano.StakeCSMT.CSMT.Codecs
    ( EpochRoot (..)
    )
import Cardano.StakeCSMT.E2E.Genesis
    ( e2eGenesisStake
    , e2eGenesisStakingCredential
    , genesisDir
    )
import Cardano.StakeCSMT.HTTP.API
    ( HistoryRootResponse (..)
    , LatestHeaderResponse (..)
    , ReadyResponse (..)
    , StakeProofResponse (..)
    , StakeRootResponse (..)
    , parseHashBase16
    , renderCredentialBase16
    )
import Cardano.StakeCSMT.HTTP.Base16
    ( decodeBase16Text
    )
import Cardano.StakeCSMT.HTTP.Signing
    ( verifyLatestHeader
    )
import Control.Concurrent
    ( forkFinally
    , killThread
    , threadDelay
    )
import Control.Concurrent.MVar
    ( MVar
    , newEmptyMVar
    , putMVar
    , readMVar
    , tryReadMVar
    )
import Control.Exception
    ( IOException
    , SomeException
    , bracket
    , displayException
    , try
    )
import Data.Aeson
    ( FromJSON
    , eitherDecode
    )
import Data.ByteString
    ( ByteString
    )
import Data.ByteString qualified as BS
import Data.ByteString qualified as ByteString
import Data.ByteString.Char8 qualified as ByteString.Char8
import Data.ByteString.Lazy qualified as ByteString.Lazy
import Data.Text qualified as Text
import Network.Socket
    ( Family (AF_INET)
    , SockAddr (SockAddrInet)
    , Socket
    , SocketOption (ReuseAddr)
    , SocketType (Stream)
    , bind
    , close
    , connect
    , defaultProtocol
    , setSocketOption
    , socket
    , socketPort
    , tupleToHostAddress
    , withSocketsDo
    )
import Network.Socket.ByteString qualified
import System.FilePath
    ( takeDirectory
    , (</>)
    )
import System.IO.Temp
    ( withSystemTempDirectory
    )
import System.Timeout
    ( timeout
    )
import Test.Hspec
    ( Expectation
    , Spec
    , describe
    , expectationFailure
    , it
    , shouldBe
    , shouldSatisfy
    )
import Text.Read
    ( readMaybe
    )

spec :: Spec
spec =
    describe "Live HTTP proof e2e"
        $ it "serves and verifies a signed voting proof over live HTTP"
        $ withCardanoNode genesisDir
        $ \socketPath _startMs ->
            withSystemTempDirectory "stake-csmt-e2e-live-http"
                $ \root ->
                    withSocketsDo $ do
                        apiPort <- reserveLocalPort
                        let nodeRuntimeDir = takeDirectory socketPath
                            config =
                                RuntimeConfig
                                    { configNodeSocketPath = socketPath
                                    , configNetworkMagic = 42
                                    , configByronEpochSlots = 21_600
                                    , configLedgerConfigDir = nodeRuntimeDir
                                    , configDbPath = root </> "store.db"
                                    , configCheckpointDir =
                                        Just $ root </> "checkpoints"
                                    , configSigningKeyPath = Nothing
                                    , configSigningKey = Just signingKey
                                    , configPort = apiPort
                                    , configDocsPort = Nothing
                                    }
                        withDaemon config $ \daemonDone -> do
                            waitUntilReady daemonDone apiPort
                            roots <-
                                getJSON
                                    apiPort
                                    "/roots"
                            roots `shouldSatisfy` (not . null)

                            proof <-
                                getJSON apiPort proofPath
                            verifyProofFromWire roots proof

                            HistoryRootResponse{historyRoot} <-
                                getJSON
                                    apiPort
                                    "/history-root"
                            historyRoot `shouldSatisfy` (not . Text.null)

                            header <-
                                getJSON
                                    apiPort
                                    "/latest-header"
                            verifyLatestHeader header `shouldBe` True
                            verifyLatestHeaderMatchesRoots roots header

type DaemonResult = Either SomeException ()

reserveLocalPort :: IO Int
reserveLocalPort =
    bracket acquire close (fmap fromIntegral . socketPort)
  where
    acquire :: IO Socket
    acquire = do
        sock <- socket AF_INET Stream defaultProtocol
        setSocketOption sock ReuseAddr 1
        bind sock $ SockAddrInet 0 $ tupleToHostAddress (127, 0, 0, 1)
        pure sock

withDaemon :: RuntimeConfig -> (MVar DaemonResult -> IO a) -> IO a
withDaemon config action =
    bracket start stop $ \(_thread, done) ->
        action done
  where
    start = do
        done <- newEmptyMVar
        thread <- forkFinally (Runtime.run config) (putMVar done)
        pure (thread, done)

    stop (thread, done) = do
        killThread thread
        _ <- timeout 10_000_000 $ readMVar done
        pure ()

waitUntilReady :: MVar DaemonResult -> Int -> IO ()
waitUntilReady daemonDone apiPort = do
    result <- timeout 120_000_000 poll
    case result of
        Nothing ->
            expectationFailure
                "timed out waiting for GET /ready to report ready = true"
        Just () ->
            pure ()
  where
    poll = do
        expectDaemonAlive daemonDone
        response <- try @IOException $ getJSON apiPort "/ready"
        case response of
            Right ReadyResponse{ready = True} ->
                pure ()
            Right ReadyResponse{ready = False} ->
                retry
            Left _notListeningYet ->
                retry

    retry = do
        threadDelay 10_000
        poll

getJSON :: (FromJSON a) => Int -> String -> IO a
getJSON apiPort path = do
    response <- getHTTP apiPort path
    either
        ( fail
            . (("failed to decode JSON from " <> path <> ": ") <>)
        )
        pure
        $ eitherDecode
        $ ByteString.Lazy.fromStrict response

getHTTP :: Int -> String -> IO ByteString
getHTTP apiPort path =
    bracket open close $ \sock -> do
        connect sock
            $ SockAddrInet
                (fromIntegral apiPort)
            $ tupleToHostAddress (127, 0, 0, 1)
        Network.Socket.ByteString.sendAll sock $ requestBytes path
        response <- recvAll sock
        parseHTTPBody path response
  where
    open =
        socket AF_INET Stream defaultProtocol

requestBytes :: String -> ByteString
requestBytes path =
    ByteString.Char8.pack
        $ "GET "
            <> path
            <> " HTTP/1.0\r\n"
            <> "Host: 127.0.0.1\r\n"
            <> "Accept: application/json\r\n"
            <> "Connection: close\r\n"
            <> "\r\n"

recvAll :: Socket -> IO ByteString
recvAll sock =
    go []
  where
    go chunks = do
        chunk <- Network.Socket.ByteString.recv sock 4096
        if ByteString.null chunk
            then pure $ ByteString.concat $ reverse chunks
            else go $ chunk : chunks

parseHTTPBody :: String -> ByteString -> IO ByteString
parseHTTPBody path response =
    case ByteString.breakSubstring "\r\n\r\n" response of
        (_headers, separatorAndBody)
            | ByteString.null separatorAndBody ->
                fail $ "missing HTTP response body for " <> path
        (headers, separatorAndBody) ->
            let statusLine = ByteString.Char8.takeWhile (/= '\r') headers
            in  case statusCode statusLine of
                    Just 200 ->
                        pure $ ByteString.drop 4 separatorAndBody
                    other ->
                        fail
                            $ "GET "
                                <> path
                                <> " returned HTTP status "
                                <> show other
                                <> ": "
                                <> ByteString.Char8.unpack statusLine

statusCode :: ByteString -> Maybe Int
statusCode statusLine =
    case ByteString.Char8.words statusLine of
        _httpVersion : code : _reason ->
            readMaybe $ ByteString.Char8.unpack code
        _ ->
            Nothing

verifyProofFromWire
    :: [StakeRootResponse]
    -> StakeProofResponse
    -> Expectation
verifyProofFromWire roots StakeProofResponse{..} = do
    credential
        `shouldBe` renderCredentialBase16 e2eGenesisStakingCredential
    stake `shouldBe` e2eGenesisStake
    matchingRoot <-
        expectJust "expected /roots to include the proof epoch"
            $ findRootForProof roots epoch
    let StakeRootResponse
            { stakeRoot = matchingStakeRoot
            , totalStake = matchingTotalStake
            } = matchingRoot
    matchingStakeRoot `shouldBe` stakeRoot
    matchingTotalStake `shouldBe` totalStake
    epochRootHash <-
        eitherExpectation "invalid stakeRoot from /roots"
            $ parseHashBase16 matchingStakeRoot
    proof <-
        expectJust "expected proofBytes to decode as a CSMT proof"
            $ parseProof =<< eitherToMaybe (decodeBase16Text proofBytes)
    verifyCredentialProof
        EpochRoot
            { epochRootHash
            , epochRootTotalStake = matchingTotalStake
            }
        e2eGenesisStakingCredential
        stake
        proof
        `shouldBe` True

verifyLatestHeaderMatchesRoots
    :: [StakeRootResponse]
    -> LatestHeaderResponse
    -> Expectation
verifyLatestHeaderMatchesRoots roots LatestHeaderResponse{..} = do
    latestRoot <-
        expectJust "expected at least one root" $ lastMaybe roots
    let StakeRootResponse
            { epoch = latestRootEpoch
            , stakeRoot = latestRootStakeRoot
            , totalStake = latestRootTotalStake
            } = latestRoot
    epoch `shouldBe` latestRootEpoch
    stakeRoot `shouldBe` latestRootStakeRoot
    totalStake `shouldBe` latestRootTotalStake

findRootForProof
    :: [StakeRootResponse]
    -> EpochNo
    -> Maybe StakeRootResponse
findRootForProof [] _proofEpoch =
    Nothing
findRootForProof (root@StakeRootResponse{epoch} : roots) proofEpoch
    | epoch == proofEpoch = Just root
    | otherwise = findRootForProof roots proofEpoch

lastMaybe :: [a] -> Maybe a
lastMaybe [] =
    Nothing
lastMaybe values =
    Just $ last values

expectJust :: String -> Maybe a -> IO a
expectJust _ (Just value) =
    pure value
expectJust context Nothing =
    fail context

eitherExpectation :: String -> Either String a -> IO a
eitherExpectation _ (Right value) =
    pure value
eitherExpectation context (Left err) =
    fail $ context <> ": " <> err

eitherToMaybe :: Either e a -> Maybe a
eitherToMaybe (Right value) =
    Just value
eitherToMaybe (Left _) =
    Nothing

expectDaemonAlive :: MVar DaemonResult -> Expectation
expectDaemonAlive done =
    tryReadMVar done >>= \case
        Nothing ->
            pure ()
        Just (Right ()) ->
            expectationFailure "daemon exited before serving live HTTP"
        Just (Left err) ->
            expectationFailure
                $ "daemon failed before serving live HTTP: "
                    <> displayException err

proofPath :: String
proofPath =
    "/proof/"
        <> Text.unpack
            (renderCredentialBase16 e2eGenesisStakingCredential)

signingKey :: SignKeyDSIGN Ed25519DSIGN
signingKey =
    genKeyDSIGN @Ed25519DSIGN $ mkSeedFromBytes $ BS.replicate 32 11
