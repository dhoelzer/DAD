<?php
/*------------------------------------------------------------------------
 * Encryption Module
 *------------------------------------------------------------------------
 * This module implements functions to permit the programmer to encrypt
 * and decrypt data using GPG functions called externally.  The library
 * acts as a PHP API to these functions.  To use this library, you must
 * set the private or public key that you wish to decrypt or encrypt with
 * respectively.  Functions have been provided to do this.  Where a 
 * private key will be used for decryptionm, you must also provide
 * the passphrase for that key.
 *
 *
 */
require_once("../lib/globalizer.php");
/*------------------------------------------------------------------------
 * void set_public_key(string $key)
 *------------------------------------------------------------------------
 * This function is used to set the key that will be used to encrypt
 * the data.  This function must be called prior to attempting to encrypt
 * data.
 */
function set_public_key($PublicKey)
{
  global $Global;
  
  add_global("PublicKey", "$PublicKey");
}

/*------------------------------------------------------------------------
 * void set_private_key(string $key)
 *------------------------------------------------------------------------
 * This function is used to set the private key that will be used to 
 * attempt to decrypt the data.
 */
function set_private_key($PrivateKey)
{
  global $Global;
  
  add_global("PrivateKey", "$PrivateKey");
}

/*------------------------------------------------------------------------
 * string encrypt($data)
 *------------------------------------------------------------------------
 * This function takes an arbitrary length $data input and encrypts it
 * using GPG and the public key set previously.  The return value is
 * a string containing the encrypted data.
 */
function encrypt($ClearText)
{
  global $Global;
  
  $PublicKey = (isset($Global["PublicKey"]) ? $Global["PublicKey"] : NULL);
  if(!$PublicKey)
  {
    write("No public key selected!  You must select a public key before ".
      "attempting to encrypt data.");
    return $ClearText;
  }
  $ClearTextFileName = tempnam("/tmp/enc", "CIS");
  $ClearTextFile = fopen($ClearTextFileName, "w");
  fwrite($ClearTextFile, "$ClearText");
  fclose($ClearTextFile);
  $CipherTextFileName = $ClearTextFileName.".gpg";
  $command = "gpg --no-tty --yes --trust-model always --homedir ../config --no-options --batch -r 'cis@wtbts.org' -e --no-default-keyring --keyring ../config/pubring.gpg $ClearTextFileName";
  system($command);
  unlink($ClearTextFileName);
  $CipherTextFile = fopen($CipherTextFileName, "r");
  $CipherText = fread($CipherTextFile, filesize($CipherTextFileName));
  fclose($CipherTextFile);
  unlink($CipherTextFileName);
  return $CipherText;
}

/*------------------------------------------------------------------------
 * string decrypt($data, $Passphrase)
 *------------------------------------------------------------------------
 * This function takes an arbitrary length $data input and encrypts it
 * using GPG and the public key set previously.  The return value is
 * a string containing the encrypted data.
 */
function decrypt($CipherText)
{
  global $Global;
  
  $PrivateKey = (isset($Global["PrivateKey"]) ? $Global["PrivateKey"] : NULL);
  if(!$PublicKey)
  {
    write("No private key selected!  You must select a private key before ".
      "attempting to decrypt data.");
    return $ClearText;
  }
  $ClearTextFileName = tempnam("/tmp/enc", "CIS");
  $CipherTextFileName = $ClearTextFileName . ".gpg";
  $CipherTextFile = fopen($CipherTextFileName, "w");
  fwrite($CipherTextFile, "$CipherText");
  fclose($CipherTextFile);
  $command = "echo $Passphrase | gpg --passphrase-fd 0 --no-tty --yes --trust-model always --homedir ../config --no-options --batch --no-default-keyring --secret-keyring ../config/secring.gpg --output $ClearTextFileName --decrypt $CipherTextFile";
  system($command);
  unlink($CipherTextFileName);
  $ClearTextFile = fopen($ClearTextFileName, "r");
  $ClearText = fread($ClearTextFile, filesize($ClearTextFileName));
  fclose($ClearTextFile);
  unlink($ClearTextFileName);
  return $ClearText;
}