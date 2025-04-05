#!/bin/bash
# Script per installare GRUB in automatico in un ambiente live di Arch Linux
# Deve essere eseguito come root.
# Lo script rileva automaticamente la partizione EFI e quella root, monta le partizioni necessarie, esegue il chroot e installa GRUB.
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

# Verifica che la partizione EFI sia di tipo vfat
EFI_TYPE=$(blkid -o value -s TYPE "$EFI_DEV")
if [ "$EFI_TYPE" != "vfat" ]; then
  echo "La partizione rilevata ($EFI_DEV) non sembra essere vfat (tipo rilevato: $EFI_TYPE)."
  echo "Verifica manualmente e riprova."
  exit 1
fi
echo "Partizione EFI rilevata: $EFI_DEV"

# Rileva la partizione root Linux cercando un filesystem tipico (ext4, btrfs, xfs)
ROOT_PART=$(lsblk -o NAME,TYPE,FSTYPE -rn | grep "part" | grep -Ei "ext4|btrfs|xfs" | head -n1 | awk '{print $1}')
if [ -z "$ROOT_PART" ]; then
  echo "Non sono riuscito a rilevare automaticamente la partizione root."
  read -p "Inserisci il dispositivo root (es. sda2): " ROOT_PART
fi
ROOT_DEV="/dev/$ROOT_PART"
echo "Partizione root rilevata: $ROOT_DEV"

# Monta la partizione root su /mnt
echo "Montando $ROOT_DEV su /mnt..."
mount "$ROOT_DEV" /mnt
if [ $? -ne 0 ]; then
  echo "Errore nel montaggio della partizione root."
  exit 1
fi

# Crea la directory per il mount dell'EFI se non esiste e monta la partizione EFI
echo "Creando la directory /mnt/boot/efi..."
mkdir -p /mnt/boot/efi
echo "Montando $EFI_DEV su /mnt/boot/efi..."
mount "$EFI_DEV" /mnt/boot/efi
if [ $? -ne 0 ]; then
  echo "Errore nel montaggio della partizione EFI."
  exit 1
fi

# Bind delle directory necessarie per il chroot
echo "Preparando l'ambiente chroot..."
mount --bind /dev /mnt/dev
mount --bind /proc /mnt/proc
mount --bind /sys /mnt/sys

# Installa GRUB in chroot
echo "Entrando in chroot per installare GRUB..."
chroot /mnt /bin/bash -c "grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB --recheck"
if [ $? -ne 0 ]; then
  echo "Errore durante l'installazione di GRUB in chroot."
  exit 1
fi

echo "Generazione del file di configurazione di GRUB..."
chroot /mnt /bin/bash -c "grub-mkconfig -o /boot/grub/grub.cfg"
if [ $? -ne 0 ]; then
  echo "Errore durante la generazione del file di configurazione di GRUB."
  exit 1
fi

echo "Installazione di GRUB completata con successo."
echo "Ora puoi uscire dal chroot, smontare le partizioni e riavviare il sistema."

# Smonta tutto
umount -R /mnt

echo "Operazione completata. Riavvia il sistema per verificare."
exit 0
