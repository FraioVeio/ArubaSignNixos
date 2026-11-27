{
  lib,
  stdenv,
  fetchurl,
  dpkg,
  asar,
  autoPatchelfHook,
  makeWrapper,
  wrapGAppsHook3,
  bash,
  procps,
  copyDesktopItems,
  makeDesktopItem,
  # Electron runtime
  alsa-lib,
  at-spi2-atk,
  at-spi2-core,
  cairo,
  cups,
  dbus,
  expat,
  glib,
  gtk3,
  libdrm,
  libgbm,
  libxkbcommon,
  nspr,
  nss,
  pango,
  libx11,
  libxcomposite,
  libxdamage,
  libxext,
  libxfixes,
  libxrandr,
  libxrender,
  libxtst,
  libxi,
  libxcb,
  libGL,
  systemd,
  # JRE / smartcard
  zlib,
  pcsclite,
  freetype,
  fontconfig,
  # Hide ArubaSign's built-in updater prompt (see README).
  disableUpdateNotifications ? true,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "arubasign-unwrapped";
  version = "3.6.0";

  src = fetchurl {
    # "latest" is a moving target: when Aruba publishes a new release the hash
    # changes and must be updated here (see README).
    url = "https://updatesfirma.aruba.it/downloads/ArubaSign-latest-LINUX.deb";
    hash = "sha256-888EZpauqvizC7G8hlaWPWnD5KAAmWgN33N3/cLN0OE=";
  };

  nativeBuildInputs = [
    dpkg
    asar
    autoPatchelfHook
    makeWrapper
    wrapGAppsHook3
    copyDesktopItems
  ];

  buildInputs = [
    stdenv.cc.cc.lib
    alsa-lib
    at-spi2-atk
    at-spi2-core
    cairo
    cups
    dbus
    expat
    glib
    gtk3
    libdrm
    libgbm
    libxkbcommon
    nspr
    nss
    pango
    libx11
    libxcomposite
    libxdamage
    libxext
    libxfixes
    libxrandr
    libxrender
    libxtst
    libxi
    libxcb
    zlib
    pcsclite
  ];

  # The wrapper is created by hand in postFixup (with gappsWrapperArgs).
  dontWrapGApps = true;

  unpackPhase = ''
    runHook preUnpack
    dpkg-deb --fsys-tarfile $src | tar -x --no-same-permissions --no-same-owner
    runHook postUnpack
  '';

  dontConfigure = true;
  dontBuild = true;
  # Stripping Electron / JVM binaries is useless and may break them.
  dontStrip = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/opt $out/bin $out/share/pixmaps
    cp -r opt/arubasign $out/opt/arubasign
    cp usr/share/pixmaps/arubasign.png $out/share/pixmaps/arubasign.png

    app=$out/opt/arubasign/app/lin-x64
    asp=$out/opt/arubasign/asp/lin-x64

    # Not usable from the read-only store (needs setuid root); the app is
    # started with --no-sandbox anyway, as the upstream launcher does.
    rm -f $app/chrome-sandbox
    # Self-update helper scripts, meaningless in the Nix store.
    rm -f $app/preinstall.sh $app/postinstall.sh $app/arubasign.bat

    chmod +x $app/ArubaSign $asp/ArubaSignPlatform.exe $asp/driver/util/*.exe
    # jspawnhelper is required by Java's ProcessBuilder (used to start the
    # smartcard helpers); upstream's postinst marks the whole runtime +x.
    chmod +x $out/opt/arubasign/runtime/jreLin64/bin/* \
      $out/opt/arubasign/runtime/jreLin64/lib/{jspawnhelper,jexec}

    # Point the Java smartcard API at the Nix pcsc-lite library instead of the
    # hard-coded /usr/lib path.
    printf '\n%s\n' "-Dsun.security.smartcardio.library=${lib.getLib pcsclite}/lib/libpcsclite.so.1" \
      >> $asp/ArubaSignPlatform.lap

    ${lib.optionalString disableUpdateNotifications ''
      # The built-in updater would replace the app outside of Nix, and the
      # public .deb lags behind what the updater offers, so the prompt shows
      # up on every start. Neutralise it in the GUI bundle: the update state
      # is always "NONE" and the backend's download/apply events are ignored.
      # --replace-fail makes the build stop if a new release changes the code.
      asar extract $app/resources/app.asar asar-src
      substituteInPlace asar-src/main.*.js \
        --replace-fail \
          'hasUpdate:(yr.update_status||v.Y0S.NONE)!==v.Y0S.NONE,status:yr.update_status||v.Y0S.NONE' \
          'hasUpdate:!1,status:v.Y0S.NONE' \
        --replace-fail \
          's=>{s.data&&this.eventUpdateDownload$.next(s.data)}' \
          's=>{}' \
        --replace-fail \
          's=>{s.data&&this.eventUpdateApply$.next(s.data)}' \
          's=>{}'
      asar pack asar-src $app/resources/app.asar
      rm -rf asar-src
    ''}
    install -Dm755 ${./launcher.sh} $out/libexec/arubasign-launcher
    substituteInPlace $out/libexec/arubasign-launcher \
      --subst-var-by bash ${bash} \
      --subst-var-by procps ${procps} \
      --subst-var-by src $out/opt/arubasign

    runHook postInstall
  '';

  preFixup = ''
    addAutoPatchelfSearchPath $out/opt/arubasign/runtime/jreLin64/lib
    addAutoPatchelfSearchPath $out/opt/arubasign/runtime/jreLin64/lib/server
    addAutoPatchelfSearchPath $out/opt/arubasign/app/lin-x64
  '';

  postFixup = ''
    makeWrapper $out/libexec/arubasign-launcher $out/bin/arubasign \
      "''${gappsWrapperArgs[@]}" \
      --add-flags "--no-sandbox" \
      --prefix LD_LIBRARY_PATH : "${
        lib.makeLibraryPath [
          libGL
          systemd
          pcsclite
          fontconfig
          freetype
        ]
      }"
  '';

  desktopItems = [
    (makeDesktopItem {
      name = "arubasign";
      desktopName = "ArubaSign";
      genericName = "Digital Signature Client";
      comment = "Aruba Firma Digitale – sign documents with your smartcard";
      exec = "arubasign %U";
      icon = "arubasign";
      categories = [
        "Office"
        "Utility"
      ];
      keywords = [
        "firma"
        "digitale"
        "smartcard"
        "signature"
        "aruba"
        "pec"
      ];
      startupNotify = true;
    })
  ];

  meta = {
    description = "ArubaSign – Aruba digital signature client";
    homepage = "https://www.pec.it";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "arubasign";
  };
})
