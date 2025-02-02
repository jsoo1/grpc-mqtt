-- Copyright (c) 2021 Arista Networks, Inc.
-- Use of this source code is governed by the Apache License 2.0
-- that can be found in the COPYING file.
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE TemplateHaskellQuotes #-}

-- |
module Network.GRPC.MQTT.Types
  ( -- * Session Id
    SessionId,

    -- * MQTT Requests
    MQTTRequest
      ( MQTTNormalRequest,
        MQTTWriterRequest,
        MQTTReaderRequest,
        MQTTBiDiRequest
      ),
    requestTimeout,
    requestMetadata,
    MQTTResult (..),
    MethodMap,
    RemoteResult (..),
    ClientHandler (..),
  )
where

--------------------------------------------------------------------------------

import Network.GRPC.HighLevel.Client
  ( ClientResult,
    GRPCMethodType (BiDiStreaming, ClientStreaming, Normal, ServerStreaming),
    MetadataMap,
    StreamRecv,
    StreamSend,
    TimeoutSeconds,
    WritesDone,
  )
import Network.GRPC.LowLevel (GRPCIOError)
import Network.GRPC.LowLevel.Client
  ( ClientRWHandler,
    ClientRWResult,
    ClientReaderHandler,
    ClientReaderResult,
    ClientWriterHandler,
    ClientWriterResult,
    NormalRequestResult,
  )

import Relude

import Text.Show qualified as Show

--------------------------------------------------------------------------------

-- | Represents the session ID for a request
type SessionId = Text

-- | Analogous of 'ClientRequest' from grpc-haskell with the unused fields removed
data MQTTRequest :: GRPCMethodType -> Type -> Type -> Type where
  MQTTNormalRequest ::
    rqt ->
    TimeoutSeconds ->
    MetadataMap ->
    MQTTRequest 'Normal rqt rsp
  MQTTWriterRequest ::
    TimeoutSeconds ->
    MetadataMap ->
    (StreamSend rqt -> IO ()) ->
    MQTTRequest 'ClientStreaming rqt rsp
  MQTTReaderRequest ::
    rqt ->
    TimeoutSeconds ->
    MetadataMap ->
    (MetadataMap -> StreamRecv rsp -> IO ()) ->
    MQTTRequest 'ServerStreaming rqt rsp
  MQTTBiDiRequest ::
    TimeoutSeconds ->
    MetadataMap ->
    (MetadataMap -> StreamRecv rsp -> StreamSend rqt -> WritesDone -> IO ()) ->
    MQTTRequest 'BiDiStreaming rqt rsp

-- | Retrieve a MQTT request's metadata.
--
-- @since 0.1.0.0
requestMetadata :: MQTTRequest s rqt rsp -> MetadataMap
requestMetadata (MQTTNormalRequest _ _ ms) = ms
requestMetadata (MQTTWriterRequest _ ms _) = ms
requestMetadata (MQTTReaderRequest _ _ ms _) = ms
requestMetadata (MQTTBiDiRequest _ ms _) = ms

-- | Retrieve a MQTT request's timeout period.
--
-- @since 0.1.0.0
requestTimeout :: MQTTRequest s rqt rsp -> TimeoutSeconds
requestTimeout (MQTTNormalRequest _ t _) = t
requestTimeout (MQTTWriterRequest t _ _) = t
requestTimeout (MQTTReaderRequest _ t _ _) = t
requestTimeout (MQTTBiDiRequest t _ _) = t

-- | @since 0.1.0.0
instance Show rqt => Show (MQTTRequest s rqt rsp) where
  show (MQTTNormalRequest x timeout metadata) =
    intercalate " " [show 'MQTTNormalRequest, show x, show timeout, show metadata]
  show (MQTTWriterRequest timeout metadata _) =
    intercalate " " [show 'MQTTWriterRequest, show timeout, show metadata]
  show (MQTTReaderRequest x timeout metadata _) =
    intercalate " " [show 'MQTTReaderRequest, show x, show timeout, show metadata]
  show (MQTTBiDiRequest timeout metadata _) =
    intercalate " " [show 'MQTTBiDiRequest, show timeout, show metadata]
  {-# INLINE show #-}

--------------------------------------------------------------------------------

-- | The result of a gRPC request that makes a distinction between
-- errors that occured as part of the GRPC call itself, or in the MQTT handling.
data MQTTResult streamtype response
  = MQTTError Text
  | GRPCResult (ClientResult streamtype response)

--------------------------------------------------------------------------------

-- | A map from gRPC method names to their corresponding handler
type MethodMap = HashMap ByteString ClientHandler

-- | Response received from a remote gRPC service
data RemoteResult (streamType :: GRPCMethodType) where
  RemoteNormalResult :: NormalRequestResult -> RemoteResult 'Normal
  RemoteWriterResult :: ClientWriterResult -> RemoteResult 'ClientStreaming
  RemoteReaderResult :: ClientReaderResult -> RemoteResult 'ServerStreaming
  RemoteBiDiResult :: ClientRWResult -> RemoteResult 'BiDiStreaming
  RemoteErrorResult :: GRPCIOError -> RemoteResult streamType

-- | Client gRPC handlers used by the remote gRPC client to make requests
data ClientHandler
  = ClientUnaryHandler (ByteString -> TimeoutSeconds -> MetadataMap -> IO (RemoteResult 'Normal))
  | ClientClientStreamHandler (TimeoutSeconds -> MetadataMap -> ClientWriterHandler -> IO (RemoteResult 'ClientStreaming))
  | ClientServerStreamHandler (ByteString -> TimeoutSeconds -> MetadataMap -> ClientReaderHandler -> IO (RemoteResult 'ServerStreaming))
  | ClientBiDiStreamHandler (TimeoutSeconds -> MetadataMap -> ClientRWHandler -> IO (RemoteResult 'BiDiStreaming))
