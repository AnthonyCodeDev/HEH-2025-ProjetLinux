## Instructions d'utilisation du script `set-vpn-ip-dns.ps1`

Ce fichier README vous guide pour lancer correctement le script PowerShell qui configure automatiquement l'adresse IP et le ou les serveurs DNS sur un adaptateur TAP OpenVPN.

### Prérequis

* Windows 10 / Windows 11
* Installation d'OpenVPN avec l'adaptateur `TAP-Windows Adapter V9`
* Droits d'administrateur sur la machine

### Étapes pour exécuter le script

1. **Ouvrir PowerShell en mode Administrateur**

   * Cliquez sur le menu **Démarrer**, tapez **PowerShell**, faites un clic droit sur **Windows PowerShell**, puis sélectionnez **Exécuter en tant qu’administrateur**.

2. **Se positionner dans le dossier du script**
   Utilisez la commande `cd` pour naviguer jusqu’au répertoire contenant `set-vpn-ip-dns.ps1`. Par exemple :

   ```powershell
   cd C:\chemin\vers\votre\dossier\scripts
   ```

3. **Autoriser l’exécution de scripts** (paramètre temporaire)

   ```powershell
   Set-ExecutionPolicy Bypass -Scope Process -Force
   ```

4. **Lancer le script avec les paramètres DNS**

   * **Paramètre obligatoire** : `-dns1` pour le serveur DNS principal
   * **Paramètre optionnel** : `-dns2` pour le serveur DNS secondaire

   ```powershell
   .\set-vpn-ip-dns.ps1 -dns1 <Adresse_IP_DNS_Principal> [-dns2 <Adresse_IP_DNS_Secondaire>]
   ```

   **Exemples** :

   ```powershell
   .\set-vpn-ip-dns.ps1 -dns1 10.42.0.75
   .\set-vpn-ip-dns.ps1 -dns1 10.42.0.75 -dns2 8.8.8.8
   ```

5. **Vérifier la configuration**
   Après exécution, vous pouvez vérifier que l’IP et les DNS ont bien été appliqués :

   ```powershell
   Get-NetIPAddress -InterfaceIndex <Index_TAP>
   Get-DnsClientServerAddress -InterfaceIndex <Index_TAP>
   ```

---

Pour toute question ou problème, assurez-vous que votre adaptateur OpenVPN est installé et en état **Up** dans la liste des adaptateurs réseau (\`Get-NetAd
