{
  buildFHSEnv,
  arubasign-unwrapped,
  coreutils,
  pcsclite,
  stdenv,
}:

# ArubaSign's smartcard helpers hard-code FHS paths (/bin/mkdir, /bin/cp,
# /bin/chmod to deploy the HID->CCID converter, and /usr/lib lookups for
# libpcsclite.so.1). Run the application inside a lightweight FHS sandbox
# (bubblewrap) that provides them; $HOME, /tmp and /run are shared with the
# host, so pcscd and the user's files are reachable as usual.
buildFHSEnv {
  pname = "arubasign";
  inherit (arubasign-unwrapped) version;

  targetPkgs = _: [
    arubasign-unwrapped
    coreutils
    pcsclite
    stdenv.cc.cc.lib
  ];

  runScript = "${arubasign-unwrapped}/bin/arubasign";

  extraInstallCommands = ''
    mkdir -p $out/share
    cp -r ${arubasign-unwrapped}/share/applications $out/share/
    cp -r ${arubasign-unwrapped}/share/pixmaps $out/share/
  '';

  passthru.unwrapped = arubasign-unwrapped;

  inherit (arubasign-unwrapped) meta;
}
