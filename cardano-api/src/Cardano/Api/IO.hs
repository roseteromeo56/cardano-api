{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Cardano.Api.IO
  ( readByteStringFile
  , readLazyByteStringFile
  , readTextFile
  , readFileBlocking
  , writeByteStringFileWithOwnerPermissions
  , writeByteStringFile
  , writeByteStringOutput
  , writeLazyByteStringFileWithOwnerPermissions
  , writeLazyByteStringFile
  , writeLazyByteStringOutput
  , writeTextFileWithOwnerPermissions
  , writeTextFile
  , writeTextOutput
  , File (..)
  , FileDirection (..)
  , SocketPath
  , mapFile
  , onlyIn
  , onlyOut
  , intoFile
  , checkVrfFilePermissions
  , writeSecrets
  )
where

import Cardano.Api.Error (FileError (..), fileIOExceptT)
import Cardano.Api.IO.Internal.Base
import Cardano.Api.IO.Internal.Compat

import Control.Exception (bracket)
import Control.Monad.Except (runExceptT)
import Control.Monad.IO.Class (MonadIO (..))
import Control.Monad.Trans.Except.Extra (handleIOExceptT)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Builder qualified as Builder
import Data.ByteString.Char8 qualified as BSC
import Data.ByteString.Lazy qualified as LBS
import Data.ByteString.Lazy qualified as LBSC
import Data.Text (Text)
import Data.Text.IO qualified as Text
import GHC.IO.Handle.FD (openFileBlocking)
import System.IO (IOMode (ReadMode), hClose)

readByteStringFile
  :: ()
  => MonadIO m
  => File content In
  -> m (Either (FileError e) ByteString)
readByteStringFile fp =
  runExceptT $
    fileIOExceptT (unFile fp) BS.readFile

readLazyByteStringFile
  :: ()
  => MonadIO m
  => File content In
  -> m (Either (FileError e) LBS.ByteString)
readLazyByteStringFile fp =
  runExceptT $
    fileIOExceptT (unFile fp) LBS.readFile

readTextFile
  :: ()
  => MonadIO m
  => File content In
  -> m (Either (FileError e) Text)
readTextFile fp =
  runExceptT $
    fileIOExceptT (unFile fp) Text.readFile

readFileBlocking :: FilePath -> IO BS.ByteString
readFileBlocking path =
  bracket
    (openFileBlocking path ReadMode)
    hClose
    ( \fp -> do
        -- An arbitrary block size.
        let blockSize = 4096
        let go acc = do
              next <- BS.hGet fp blockSize
              if BS.null next
                then pure acc
                else go (acc <> Builder.byteString next)
        contents <- go mempty
        pure $ LBS.toStrict $ Builder.toLazyByteString contents
    )

writeByteStringFile
  :: ()
  => MonadIO m
  => File content Out
  -> ByteString
  -> m (Either (FileError e) ())
writeByteStringFile fp bs =
  runExceptT $
    handleIOExceptT (FileIOError (unFile fp)) $
      BS.writeFile (unFile fp) bs

writeByteStringFileWithOwnerPermissions
  :: FilePath
  -> BS.ByteString
  -> IO (Either (FileError e) ())
writeByteStringFileWithOwnerPermissions fp bs =
  handleFileForWritingWithOwnerPermission fp $ \h ->
    BS.hPut h bs

writeByteStringOutput
  :: ()
  => MonadIO m
  => Maybe (File content Out)
  -> ByteString
  -> m (Either (FileError e) ())
writeByteStringOutput mOutput bs = runExceptT $
  case mOutput of
    Just fp -> handleIOExceptT (FileIOError (unFile fp)) $ BS.writeFile (unFile fp) bs
    Nothing -> liftIO $ BSC.putStr bs

writeLazyByteStringFile
  :: ()
  => MonadIO m
  => File content Out
  -> LBS.ByteString
  -> m (Either (FileError e) ())
writeLazyByteStringFile fp bs =
  runExceptT $
    handleIOExceptT (FileIOError (unFile fp)) $
      LBS.writeFile (unFile fp) bs

writeLazyByteStringFileWithOwnerPermissions
  :: File content Out
  -> LBS.ByteString
  -> IO (Either (FileError e) ())
writeLazyByteStringFileWithOwnerPermissions fp lbs =
  handleFileForWritingWithOwnerPermission (unFile fp) $ \h ->
    LBS.hPut h lbs

writeLazyByteStringOutput
  :: ()
  => MonadIO m
  => Maybe (File content Out)
  -> LBS.ByteString
  -> m (Either (FileError e) ())
writeLazyByteStringOutput mOutput bs = runExceptT $
  case mOutput of
    Just fp -> handleIOExceptT (FileIOError (unFile fp)) $ LBS.writeFile (unFile fp) bs
    Nothing -> liftIO $ LBSC.putStr bs

writeTextFile
  :: ()
  => MonadIO m
  => File content Out
  -> Text
  -> m (Either (FileError e) ())
writeTextFile fp t =
  runExceptT $
    handleIOExceptT (FileIOError (unFile fp)) $
      Text.writeFile (unFile fp) t

writeTextFileWithOwnerPermissions
  :: File content Out
  -> Text
  -> IO (Either (FileError e) ())
writeTextFileWithOwnerPermissions fp t =
  handleFileForWritingWithOwnerPermission (unFile fp) $ \h ->
    Text.hPutStr h t

writeTextOutput
  :: ()
  => MonadIO m
  => Maybe (File content Out)
  -> Text
  -> m (Either (FileError e) ())
writeTextOutput mOutput t = runExceptT $
  case mOutput of
    Just fp -> handleIOExceptT (FileIOError (unFile fp)) $ Text.writeFile (unFile fp) t
    Nothing -> liftIO $ Text.putStr t

mapFile :: (FilePath -> FilePath) -> File content direction -> File content direction
mapFile f = File . f . unFile

onlyIn :: File content InOut -> File content In
onlyIn = File . unFile

onlyOut :: File content InOut -> File content Out
onlyOut = File . unFile

-- | Given a way to serialise a value and a way to write the stream to a file, serialise
-- a value into a stream, and write it to a file.
--
-- Whilst it is possible to call the serialisation and writing functions separately,
-- doing so means the compiler is unable to match the content type of the file with
-- the type of the content being serialised.
--
-- Using this function ensures that the content type of the file always matches with the
-- content value and prevents any type mismatches.
intoFile
  :: ()
  => File content 'Out
  -> content
  -> (File content 'Out -> stream -> result)
  -> (content -> stream)
  -> result
intoFile fp content write serialise = write fp (serialise content)
