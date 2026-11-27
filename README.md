# ArubaSign per NixOS

Flake che impacchetta [ArubaSign](https://www.pec.it), il client di firma digitale di Aruba,
a partire dal `.deb` ufficiale.

## Uso rapido

```sh
nix run github:FraioVeio/ArubaSignNixos   # oppure, in locale:
nix run .
```

## Installazione

Aggiungi il flake agli input della tua configurazione:

```nix
inputs.arubasign.url = "github:FraioVeio/ArubaSignNixos";
```

Poi scegli uno dei modi seguenti.

### 1. Modulo NixOS (sistema)

Installa ArubaSign per tutti gli utenti e abilita `pcscd`:

```nix
nixosConfigurations.<host> = nixpkgs.lib.nixosSystem {
  modules = [
    arubasign.nixosModules.default
    { programs.arubasign.enable = true; }
  ];
};
```

### 2. Pacchetto di sistema, senza modulo

```nix
environment.systemPackages = [ arubasign.packages.x86_64-linux.default ];
services.pcscd.enable = true;
```

### 3. Utente, con Home Manager

```nix
home.packages = [ arubasign.packages.x86_64-linux.default ];
```

### 4. Utente, imperativo

```sh
nix profile install github:FraioVeio/ArubaSignNixos
```

### 5. Senza installarlo

```sh
nix run github:FraioVeio/ArubaSignNixos
```

### Note

- **Smartcard e token richiedono `pcscd`**, che è un servizio di sistema: con i metodi 3, 4 e 5
  va comunque aggiunto `services.pcscd.enable = true;` alla configurazione NixOS. Senza,
  l'app parte ma non vede il lettore. La firma remota (OTP) funziona anche senza.
- **Licenza unfree:** usando `arubasign.packages.x86_64-linux.default` non serve `allowUnfree`,
  perché il flake la accetta già da solo. Se invece usi `arubasign.overlays.default` (cioè
  `pkgs.arubasign`), il tuo nixpkgs deve accettare i pacchetti `arubasign` e
  `arubasign-unwrapped`, per esempio con `nixpkgs.config.allowUnfree = true;`.
- In ogni caso i dati restano per utente, in `~/.ArubaSign` e `~/.local/share/arubasign`.

## Come funziona

- `arubasign-unwrapped` (`package.nix`): estrae il `.deb` e patcha con `autoPatchelfHook`
  Electron, il JRE incluso e i driver.
- `arubasign` (`fhs.nix`): avvolge il pacchetto in un `buildFHSEnv`, perché gli helper per le
  smartcard usano percorsi FHS fissi (`/bin/cp`, `/bin/chmod`, `/usr/lib/libpcsclite.so.1`).
- ArubaSign scrive nella propria cartella di installazione (licenza, DB dei certificati).
  Lo store Nix però è in sola lettura, quindi il launcher (`launcher.sh`) crea una copia
  scrivibile in `~/.local/share/arubasign`: symlink allo store, più copie reali degli
  eseguibili e dei database. La copia viene ricreata solo quando cambia la versione del pacchetto.
- Dati e configurazione utente restano in `~/.ArubaSign`, come su altre distribuzioni.

## Aggiornare la versione

L'URL `ArubaSign-latest-LINUX.deb` non è versionato: quando Aruba pubblica una nuova
release il build fallisce per hash mismatch. Per aggiornare:

```sh
nix store prefetch-file https://updatesfirma.aruba.it/downloads/ArubaSign-latest-LINUX.deb
```

Poi aggiorna `hash` e `version` in `package.nix`.
