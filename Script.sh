#!/bin/bash
# Script per installare GRUB in automatico in un ambiente live di Arch Linux
# Deve essere eseguito come root.
# Lo script rileva automaticamente la partizione EFI e quella root, escludendo la partizione live,
# monta le partizioni necessarie, esegue il chroot e installa GRUB.
# Se la rilevazione automatica fallisce, verrà chiesto l’input manuale.

# Verifica di essere root
if [ "$EUID" -ne 0 ]; then
  echo "Esegui questo script come root."
  exit 1
fi

echo "Rilevamento automatico delle partizioni..."

# Rileva la partizione EFI cercando in lsblk la stringa 'EFI' nel campo PARTLABEL o LABEL
EFI_PART=$(lsblk -o NAME,FSTYPE,LABEL,PARTLABEL -rn | grep -i 'EFI' | head -n1 | awk '{print $1}')
if [ -z "$EFI_PART" ]; then
  echo "Non sono riuscito a rilevare automaticamente la partizione EFI."
  read -p "Inserisci il dispositivo EFI (es. sda1): " EFI_PART
fi
EFI_DEV="/dev/$EFI_PART"

# Verifica esistenza e tipo della partizione EFI
if [ ! -b "$EFI_DEV" ]; then
  echo "Errore: $EFI_DEV non esiste."
  exit 1
fi
EFI_TYPE=$(blkid -o value -s TYPE "$EFI_DEV")
if [ "$EFI_TYPE" != "vfat" ]; then
  echo "La partizione $EFI_DEV non è di tipo vfat (tipo rilevato: $EFI_TYPE)."
  exit 1
fi
echo "Partizione EFI rilevata: $EFI_DEV"

# Rileva la partizione root escludendo quella live
LIVE_ROOT_DEV=$(findmnt -n -o SOURCE /)
LIVE_ROOT_NAME=$(basename "$LIVE_ROOT_DEV")
ROOT_PART=$(lsblk -o NAME,TYPE,FSTYPE -rn | grep "part" | grep -Ei "ext4|btrfs|xfs" | awk -v live="$LIVE_ROOT_NAME" '$1 != live' | head -n1 | awk '{print $1}')
if [ -z "$ROOT_PART" ]; then
  echo "Non sono riuscito a rilevare automaticamente la partizione root."
  read -p "Inserisci il dispositivo root (es. sda2): " ROOT_PART
fi
ROOT_DEV="/dev/$ROOT_PART"

# Verifica esistenza e tipo della partizione root
if [ ! -b "$ROOT_DEV" ]; then
  echo "Errore: $ROOT_DEV non esiste."
  exit 1
fi
if [ "$ROOT_DEV" = "$LIVE_ROOT_DEV" ]; then
  echo "Errore: $ROOT_DEV è la partizione del sistema live."
  exit 1
fi
ROOT_TYPE=$(blkid -o value -s TYPE "$ROOT_DEV")
if [[ ! "$ROOT_TYPE" =~ ^(ext4|btrfs|xfs)$ ]]; then
  echo "Filesystem non supportato per la root: $ROOT_TYPE."
  exit 1
fi
echo "Partizione root rilevata: $ROOT_DEV"

# Monta la partizione root su /mnt
echo "Montando $ROOT_DEV su /mnt..."
mount "$ROOT_DEV" /mnt || { echo "Errore nel montaggio della root."; exit 1; }

# Crea e monta la partizione EFI
echo "Creando la directory /mnt/boot/efi..."
mkdir -p /mnt/boot/efi
echo "Montando $EFI_DEV su /mnt/boot/efi..."
mount "$EFI_DEV" /mnt/boot/efi || { echo "Errore nel montaggio dell'EFI."; exit 1; }

# Bind mount per il chroot
echo "Preparando l'ambiente chroot..."
mount --bind /dev /mnt/dev
mount --bind /proc /mnt/proc
mount --bind /sys /mnt/sys

# Installazione di GRUB
echo "Installazione di GRUB in corso..."
if ! chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB --recheck; then
  echo "Errore durante l'installazione di GRUB."
  exit 1
fi

echo "Generazione del file di configurazione di GRUB..."
if ! chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg; then
  echo "Errore durante la generazione della configurazione."
  exit 1
fi

# Pulizia e finale
echo "Smontando le partizioni..."
umount -R /mnt

echo "Operazione completata con successo. Riavvia il sistema."
exit 0
