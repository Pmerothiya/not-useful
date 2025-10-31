#!/bin/bash
# =====================================================
# IBM API Connect - Unified Product Lifecycle Automation
# =====================================================

echo ""
echo "====================================================="
echo "        IBM API Connect Product Lifecycle Tool        "
echo "====================================================="

# ------------------------------------------------------
#  Load Environment File Automatically
# ------------------------------------------------------
ENV_FILE="apic_inputs.env"
if [[ -f "$ENV_FILE" ]]; then
  echo "Loading configuration from: $ENV_FILE"
  source "$ENV_FILE"
else
  echo "ERROR: Environment file '$ENV_FILE' not found."
  exit 1
fi

# ------------------------------------------------------
#  Validate Mandatory Variables
# ------------------------------------------------------
if [[ -z "$ACTION" ]]; then
  echo "ERROR: ACTION variable not set. Please define ACTION in $ENV_FILE."
  exit 1
fi

REQUIRED_VARS=("SERVER" "ORG" "CATALOG" "USERNAME" "PASSWORD" "REALM")
for var in "${REQUIRED_VARS[@]}"; do
  if [[ -z "${!var}" ]]; then
    echo "ERROR: Missing required variable: $var"
    exit 1
  fi
done

# ------------------------------------------------------
#  Login Function
# ------------------------------------------------------
login_to_apic() {
  echo ""
  echo "-----------------------------------------------------"
  echo " STEP 1: Logging in to IBM API Connect"
  echo "-----------------------------------------------------"
  apic login --server "$SERVER" --username "$USERNAME" --password "$PASSWORD" --realm "$REALM"
  if [[ $? -ne 0 ]]; then
    echo "ERROR: APIC login failed. Please check your credentials."
    exit 1
  fi
  echo "Login successful."
  echo ""
}

# ------------------------------------------------------
#  Publish Product
# ------------------------------------------------------
publish_product() {
  echo "-----------------------------------------------------"
  echo " STEP 2: Creating and Publishing Product"
  echo "-----------------------------------------------------"
  PRODUCT_FILE="${NAME}.yaml"

  apic create product \
    --title "$TITLE" \
    --name "$NAME" \
    --version "$VERSION" \
    --apis "$API_FILE"

  if [[ ! -f "$PRODUCT_FILE" ]]; then
    echo "ERROR: Product file not created: $PRODUCT_FILE"
    exit 1
  fi

  echo "Product file created: $PRODUCT_FILE"
  echo "Publishing product to $ORG > $CATALOG > $SPACE..."
  echo ""

  apic products:publish "$PRODUCT_FILE" \
    --server "$SERVER" -o "$ORG" -c "$CATALOG" \
    --scope space --space "$SPACE"

  if [[ $? -eq 0 ]]; then
    echo "Product $NAME:$VERSION published successfully."
  else
    echo "ERROR: Product publish failed."
    exit 1
  fi
}

# ------------------------------------------------------
#  Supersede Product
# ------------------------------------------------------
supersede_product() {
  echo "-----------------------------------------------------"
  echo " STEP 2: Superseding Existing Product"
  echo "-----------------------------------------------------"
  OLD_URL=$(apic products:list-all --server "$SERVER" -o "$ORG" -c "$CATALOG" \
    --scope space --space "$SPACE" | grep "${PRODUCT_SUPERSEDE}:${OLD_VERSION_SUPERSEDE}" | awk '{print $NF}')

  if [[ -z "$OLD_URL" ]]; then
    echo "ERROR: Unable to locate old product URL."
    exit 1
  fi

  cat > supersede_mapping.yaml <<EOF
product_url: "$OLD_URL"
plans:
  - source: $PLAN_SUPERSEDE
    target: $PLAN_SUPERSEDE
EOF

  apic products:supersede --server "$SERVER" -o "$ORG" -c "$CATALOG" \
    --scope space --space "$SPACE" \
    "${PRODUCT_SUPERSEDE}:${NEW_VERSION_SUPERSEDE}" supersede_mapping.yaml

  if [[ $? -eq 0 ]]; then
    echo "Product superseded successfully."
  else
    echo "ERROR: Supersede operation failed."
    exit 1
  fi

  rm -f supersede_mapping.yaml
}

# ------------------------------------------------------
#  Replace Product
# ------------------------------------------------------
replace_product() {
  echo "-----------------------------------------------------"
  echo " STEP 2: Replacing Existing Product"
  echo "-----------------------------------------------------"
  OLD_URL=$(apic products:list-all --server "$SERVER" -o "$ORG" -c "$CATALOG" \
    --scope space --space "$SPACE" | grep "${OLD_PRODUCT_REPLACE}:${OLD_VERSION_REPLACE}" | awk '{print $NF}')

  if [[ -z "$OLD_URL" ]]; then
    echo "ERROR: Unable to locate old product URL."
    exit 1
  fi

  cat > replace_mapping.yaml <<EOF
product_url: "$OLD_URL"
plans:
  - source: $PLAN_REPLACE
    target: $PLAN_REPLACE
EOF

  apic products:replace --server "$SERVER" -o "$ORG" -c "$CATALOG" \
    --scope space --space "$SPACE" \
    "${OLD_PRODUCT_REPLACE}:${NEW_VERSION_REPLACE}" replace_mapping.yaml

  if [[ $? -eq 0 ]]; then
    echo "Product replaced successfully."
  else
    echo "ERROR: Replace operation failed."
    exit 1
  fi

  rm -f replace_mapping.yaml
}

# ------------------------------------------------------
#  Deprecate Product
# ------------------------------------------------------
deprecate_product() {
  echo "-----------------------------------------------------"
  echo " STEP 2: Deprecating Product"
  echo "-----------------------------------------------------"

  cat > deprecate_product.yaml <<EOF
state: deprecated
EOF

  apic products:update --server "$SERVER" -o "$ORG" -c "$CATALOG" \
    --scope space --space "$SPACE" \
    "${PRODUCT_DEPRECATE}:${VERSION_DEPRECATE}" deprecate_product.yaml

  if [[ $? -eq 0 ]]; then
    echo "Product deprecated successfully."
  else
    echo "ERROR: Deprecate operation failed."
    exit 1
  fi

  rm -f deprecate_product.yaml
}

# ------------------------------------------------------
#  Retire Product
# ------------------------------------------------------
retire_product() {
  echo "-----------------------------------------------------"
  echo " STEP 2: Retiring Product"
  echo "-----------------------------------------------------"

  cat > retire_product.yaml <<EOF
state: retired
EOF

  apic products:update --server "$SERVER" -o "$ORG" -c "$CATALOG" \
    --scope space --space "$SPACE" \
    "${PRODUCT_RETIRE}:${VERSION_RETIRE}" retire_product.yaml

  if [[ $? -eq 0 ]]; then
    echo "Product retired successfully."
  else
    echo "ERROR: Retire operation failed."
    exit 1
  fi

  rm -f retire_product.yaml
}

# ------------------------------------------------------
#  Operation Dispatcher
# ------------------------------------------------------
login_to_apic

case "$ACTION" in
  publish)   publish_product ;;
  supersede) supersede_product ;;
  replace)   replace_product ;;
  deprecate) deprecate_product ;;
  retire)    retire_product ;;
  *)
    echo "ERROR: Invalid ACTION specified. Use one of:"
    echo "       publish | supersede | replace | deprecate | retire"
    exit 1
    ;;
esac

# ------------------------------------------------------
#  Completion Summary
# ------------------------------------------------------
echo ""
echo "====================================================="
echo "   APIC $ACTION operation completed successfully.     "
echo "====================================================="