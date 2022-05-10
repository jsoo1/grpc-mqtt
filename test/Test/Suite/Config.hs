{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE ImportQualifiedPost #-}
{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE ImplicitPrelude #-}

-- | TODO
module Test.Suite.Config
  ( -- * Test Suite Configuration
    -- $test-suite-configuration
    TestConfig
      ( TestConfig,
        testConfigBrokerPort,
        testConfigServerPort,
        testConfigServerHost,
        testConfigBaseTopic
      ),
    withTestConfig,

    -- * Query Test Config
    askServiceOptions,
    askConfigClientGRPC,
    askConfigClientMQTT,

    -- * Test Suite Options
    -- $test-suite-options
    TestOption (TestOption, getTestOption),
    askTestOption,
  )
where

--------------------------------------------------------------------------------

import Test.Tasty (TestTree)
import Test.Tasty qualified as Tasty
import Test.Tasty.Options
  ( IsOption,
    defaultValue,
    optionHelp,
    optionName,
    parseValue,
    safeRead,
  )

--------------------------------------------------------------------------------

import Control.Monad.Cont (cont, runCont)
import Control.Monad.Reader

import Data.Default (def)
import Data.Kind (Type)
import Data.Typeable (Typeable)

import Data.ByteString.Char8 qualified as ByteString.Char8
import Data.String (fromString)

import GHC.TypeLits (Symbol)

import Network.Connection (TLSSettings (TLSSettings))

import Network.GRPC.HighLevel.Client (ClientConfig, Host, Port)
import Network.GRPC.HighLevel.Client qualified as GRPC.Client
import Network.GRPC.HighLevel.Generated (ServiceOptions)
import Network.GRPC.HighLevel.Generated qualified as GRPC.Generated

import Network.MQTT.Topic (Topic)

import Network.TLS (defaultParamsClient)
import Network.TLS qualified as TLS
import Network.TLS.Extra.Cipher (ciphersuite_default)

--------------------------------------------------------------------------------

import Network.GRPC.MQTT.Core (MQTTGRPCConfig)
import Network.GRPC.MQTT.Core qualified as GRPC.MQTT

--------------------------------------------------------------------------------

-- $test-suite-configuration
--
-- TODO

-- | TODO
data TestConfig = TestConfig
  { testConfigBrokerPort :: Port
  , testConfigServerPort :: Port
  , testConfigServerHost :: Host
  , testConfigBaseTopic :: Topic
  }
  deriving (Eq, Show)

-- | TODO
withTestConfig :: (TestConfig -> TestTree) -> TestTree
withTestConfig = runCont do
  brokerPort <- cont (askTestOption @"broker-port")
  serverPort <- cont (askTestOption @"server-port")
  serverHost <- cont (askTestOption @"server-host")
  baseTopic <- cont (askTestOption @"base-topic")
  let config :: TestConfig
      config =
        TestConfig
          { testConfigBrokerPort = brokerPort
          , testConfigServerPort = serverPort
          , testConfigServerHost = serverHost
          , testConfigBaseTopic = baseTopic
          }
   in pure config

-- | TODO
askServiceOptions :: MonadReader TestConfig m => m ServiceOptions
askServiceOptions = do
  port <- asks testConfigServerPort
  pure GRPC.Generated.defaultServiceOptions{GRPC.Generated.serverPort = port}

-- | TODO
askConfigClientGRPC :: MonadReader TestConfig m => m ClientConfig
askConfigClientGRPC = do
  host <- asks testConfigServerHost
  port <- asks testConfigServerPort
  let config :: ClientConfig
      config =
        GRPC.Client.ClientConfig
          { GRPC.Client.clientServerHost = host
          , GRPC.Client.clientServerPort = port
          , GRPC.Client.clientArgs = []
          , GRPC.Client.clientSSLConfig = Nothing
          , GRPC.Client.clientAuthority = Nothing
          }
   in pure config

-- | TODO
askConfigClientMQTT :: MonadReader TestConfig m => m MQTTGRPCConfig
askConfigClientMQTT = do
  GRPC.Client.Host host <- asks testConfigServerHost
  GRPC.Client.Port port <- asks testConfigBrokerPort
  let config :: MQTTGRPCConfig
      config =
        GRPC.MQTT.defaultMGConfig
          { GRPC.MQTT._hostname = ByteString.Char8.unpack host
          , GRPC.MQTT._port = port
          , GRPC.MQTT._tlsSettings =
              TLSSettings
                (defaultParamsClient "localhost" "")
                  { TLS.clientSupported = def{TLS.supportedCiphers = ciphersuite_default}
                  }
          }
   in pure config

--------------------------------------------------------------------------------

-- $test-suite-options
--
-- TODO

-- | TODO
data TestOption (opt :: Symbol) (a :: Type) :: Type where
  TestOption :: forall opt a. {getTestOption :: a} -> TestOption opt a
  deriving (Typeable, Show)

-- | Identitical to 'Tasty.askOption' except for handling the unwrapping of
-- 'TestOption', intended to be used via type application:
--
-- >>> askTestOption @"broker-port" @Port
askTestOption :: forall opt a. IsOption (TestOption opt a) => (a -> TestTree) -> TestTree
askTestOption k =
  let continue :: TestOption opt a -> TestTree
      continue (TestOption x) = k x
   in Tasty.askOption continue

--- Tasty Option Instances ------------------------------------------------------

parsePort :: String -> Maybe Port
parsePort input = do
  port <- safeRead input
  if port <= 65_535
    then Just (GRPC.Client.Port port)
    else Nothing

instance IsOption (TestOption "broker-port" Port) where
  optionName = "broker-port"
  optionHelp = "The port used by the MQTT broker."

  -- Default port used by mosquitto
  defaultValue = TestOption @"broker-port" 1883

  parseValue = fmap (TestOption @"broker-port") . parsePort

instance IsOption (TestOption "server-port" Port) where
  optionName = "server-port"
  optionHelp = "The port used by the test gRPC services."

  defaultValue = TestOption @"server-port" 50_051

  parseValue = fmap (TestOption @"server-port") . parsePort

instance IsOption (TestOption "server-host" Host) where
  optionName = "server-host"
  optionHelp = "The hostname used by the MQTT broker and test gRPC services."

  defaultValue = TestOption @"server-host" "localhost"

  parseValue = Just . TestOption @"server-host" . GRPC.Client.Host . ByteString.Char8.pack

instance IsOption (TestOption "base-topic" Topic) where
  optionName = "base-topic"
  optionHelp = "The base topic used by the MQTT broker."

  defaultValue = TestOption @"base-topic" "testMachine/testclient"

  parseValue = Just . TestOption @"base-topic" . fromString
