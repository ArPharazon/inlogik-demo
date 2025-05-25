#!/bin/bash
set -e

# Default values
VERBOSE=false
CONTACT_EMAIL="alerts@example.com"

# Display help text
function show_help {
  echo "Usage: $0 <keyvault-name> <certificate-name> <certificate-file-name> [options]"
  echo ""
  echo "Options:"
  echo "  -p, --password PWD      Password for the certificate"
  echo "  -e, --email EMAIL       Contact email (default: alerts@example.com)"
  echo "  -v, --verbose           Enable verbose output"
  echo "  -h, --help              Show this help text"
  exit 0
}

# Log message with timestamp if verbose is enabled
function log {
  if [ "$VERBOSE" = true ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
  fi
}

# Parse command line arguments
POSITIONAL_ARGS=()
while [[ $# -gt 0 ]]; do
  case $1 in
    -p|--password)
      CERT_PASSWORD="$2"
      shift 2
      ;;
    -e|--email)
      CONTACT_EMAIL="$2"
      shift 2
      ;;
    -v|--verbose)
      VERBOSE=true
      shift
      ;;
    -h|--help)
      show_help
      ;;
    -*|--*)
      echo "Unknown option $1"
      show_help
      ;;
    *)
      POSITIONAL_ARGS+=("$1")
      shift
      ;;
  esac
done

# Restore positional parameters
set -- "${POSITIONAL_ARGS[@]}"

if [ "$#" -lt 3 ]; then
  echo "Error: Missing required parameters"
  show_help
fi

KEYVAULT_NAME="$1"
CERT_NAME="$2"
CERT_FILE="$3"
CERT_PASSWORD="${CERT_PASSWORD:-}"

# Check if Azure CLI is logged in
log "Checking Azure CLI login status..."
az account show &>/dev/null || {
  echo "Error: Not logged in to Azure CLI. Please run 'az login' first."
  exit 1
}

# Check if certificate file exists
if [ ! -f "$CERT_FILE" ]; then
  echo "Error: Certificate file not found: $CERT_FILE"
  exit 2
fi

# Import certificate into Key Vault
echo "Importing certificate '$CERT_NAME' to Key Vault '$KEYVAULT_NAME'..."
IMPORT_COMMAND="az keyvault certificate import --vault-name \"$KEYVAULT_NAME\" --name \"$CERT_NAME\" --file \"$CERT_FILE\""

if [ -n "$CERT_PASSWORD" ]; then
  IMPORT_COMMAND="$IMPORT_COMMAND --password \"$CERT_PASSWORD\""
  
  # Store certificate password as a secret
  log "Certificate has a password, will store it as a secret"
fi

log "Executing: $IMPORT_COMMAND"
eval $IMPORT_COMMAND || {
  echo "Error: Failed to import certificate"
  exit 3
}

# Store certificate password in Key Vault if provided
if [ -n "$CERT_PASSWORD" ]; then
  echo "Storing certificate password as a secret in Key Vault..."
  az keyvault secret set --vault-name "$KEYVAULT_NAME" --name "${CERT_NAME}-password" --value "$CERT_PASSWORD" >/dev/null || {
    echo "Warning: Failed to store certificate password as a secret"
  }
fi

# Add certificate contact
echo "Adding contact email '$CONTACT_EMAIL' to Key Vault certificates..."

# First check if contacts are already configured to avoid overwriting existing contacts
EXISTING_CONTACTS=$(az keyvault certificate contact list --vault-name "$KEYVAULT_NAME" -o json)
CONTACT_EXISTS=$(echo "$EXISTING_CONTACTS" | grep -c "$CONTACT_EMAIL" || true)

if [ "$CONTACT_EXISTS" -gt 0 ]; then
  echo "Contact '$CONTACT_EMAIL' is already configured for this Key Vault"
else
  # Create a temporary JSON file for contacts
  TEMP_JSON=$(mktemp)
  
  # For better management, we'll merge with existing contacts rather than replacing them
  echo '{"emailAddresses": ["'"$CONTACT_EMAIL"'"]}' > "$TEMP_JSON"
  
  # Add certificate contact
  az keyvault certificate contact add --vault-name "$KEYVAULT_NAME" --email "$CONTACT_EMAIL" || {
    echo "Warning: Failed to add certificate contact"
  }
  
  # Clean up temporary file
  rm -f "$TEMP_JSON"
fi

echo "Certificate '$CERT_NAME' has been successfully imported to Key Vault '$KEYVAULT_NAME'"
echo "Certificate contact '$CONTACT_EMAIL' has been configured"