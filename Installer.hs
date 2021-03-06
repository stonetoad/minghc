{-# LANGUAGE OverloadedStrings #-}

module Installer(installer) where

import Config
import Control.Monad
import Data.String
import Data.List.Extra
import Development.NSIS
import Development.NSIS.Plugins.EnvVarUpdate


installer :: Arch -> (Program -> Version) -> String
installer arch version = nsis $ do
    forM_ [minBound..maxBound] $ \prog ->
        constant (upper $ show prog) (fromString $ version prog :: Exp String)
    constant "ARCH" (fromString $ showArch arch :: Exp String)

    name "MinGHC-$GHC-$ARCH"
    outFile "minghc-$GHC-$ARCH.exe"
    -- See: http://stackoverflow.com/questions/1831810/is-appdata-now-the-correct-place-to-install-user-specific-apps-which-modify-t/1845459#1845459
    installDir "$LOCALAPPDATA/Programs/minghc-$GHC-$ARCH"

    page Components
    page Directory
    page InstFiles
    unpage Confirm
    unpage InstFiles

    -- important that $APPDATA/cabal/bin is first because we prepend to the PATH
    -- meaning it ends up being on the PATH lower-priority than our stuff,
    -- since the user may have their own old version of cabal in $INSTDIR
    let path =
            ["$INSTDIR/bin"
            ,"$INSTDIR/ghc-$GHC/bin"
            ,"$INSTDIR/ghc-$GHC/mingw/bin"
            ,"$INSTDIR/git-$GIT/usr/bin"
            ,"$INSTDIR/git-$GIT/cmd"
            ,"$APPDATA/cabal/bin"
            ]

    section "Install" [Required, Description "Install GHC, Cabal and PortableGit"] $ do
        setOutPath "$INSTDIR"
        writeUninstaller "uninstall.exe"

        let rootArchives = map (dest "$GHC" arch) [minBound..maxBound]
        mapM_ (file [] . fromString) rootArchives
        file [Recursive] "bin/*"

        execWait "\"$INSTDIR/bin/7z.exe\" x -y \"-o$INSTDIR/bin\" \"$INSTDIR/bin/minghc-post-install.exe.7z\""
        Development.NSIS.delete [] "$INSTDIR/bin/minghc-post-install.exe.7z"
        let quote :: String -> String
            quote x = concat ["\"", x, "\""]
        execWait $ fromString $ unwords $ map quote
            $ "$INSTDIR/bin/minghc-post-install.exe"
            : rootArchives
        Development.NSIS.delete [] "$INSTDIR/bin/minghc-post-install.exe"

        createDirectory "$INSTDIR/switch"

        let switcherAliases = [fromString ("$INSTDIR/switch/minghc" ++ x ++ ".bat") | x <- switcherNameSuffixes]
        forM_ switcherAliases $ flip writeFileLines $
            ["set PATH=" & x & ";%PATH%" | x <- path] ++
            ["ghc --version"]

    section "Add programs to PATH" [Description "Put GHC, Cabal and PortableGit on the %PATH%"] $ do
        -- Should use HKLM instead of HKCU for all but APPDATA.
        -- However, we need to ensure that the APPDATA path comes first.
        -- And this is the only way I could make that happen.
        mapM_ (setEnvVarPrepend HKCU "PATH") path

    section "Add switcher to PATH" [Description "Put minghc-$GHC.bat on the %PATH%, which puts the other programs on the %PATH%"] $ do
        setEnvVarPrepend HKCU "PATH" "$INSTDIR/switch"

    uninstall $ do
        rmdir [Recursive] "$INSTDIR"
        -- make sure we don't remove $APPDATA/cabal/bin, since users may have had that on their $PATH before
        mapM_ (setEnvVarRemove HKCU "PATH") $ "$INSTDIR/switch" : tail path

    where
        switcherNameSuffixes
            = "" -- no suffix
            : map (concatMap ('-':))
                [[showArchAbbr arch]
                ,[version GHC]
                ,[version GHC, showArchAbbr arch]
                ,[majorVersion (version GHC)]
                ,[majorVersion (version GHC), showArchAbbr arch]]

showArchAbbr :: Arch -> String
showArchAbbr Arch32 = "32"
showArchAbbr Arch64 = "64"

majorVersion :: Version -> Version
majorVersion ver = intercalate "." (take 2 parts)
    where parts = wordsBy (== '.') ver
