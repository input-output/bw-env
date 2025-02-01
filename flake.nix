{
  description = "Flake used to define terraform helper binary that can read variables from bitwarden";

  outputs =
    { ... }:
    let
      assertMsg = pred: msg: pred || builtins.throw msg;
    in
    {
      overlays.default = final: prev: {
        mkBwTerraform =
          { items }:
          let
            itemNames = builtins.attrNames items;
            exports = builtins.map (
              itemName:
              let
                item = items.${itemName};
                tfVarNames = builtins.attrNames item;
                vars = builtins.map (
                  tfVarName:
                  let
                    var = item.${tfVarName};
                    exportVarName = "TF_VAR_${tfVarName}";
                    script =
                      if var == "login.password" || var == "login.username" then
                        "jq -r '${var}'"
                      else
                        "jq -r --arg name '${var}' \"$JQ_FIELD_SCRIPT\"";
                  in
                  assert assertMsg (
                    builtins.match "^[a-zA-Z0-9_]+$" != null
                  ) "Invalid terraform variable name: ${tfVarName}";
                  ''
                    export ${exportVarName}="$(${script} <<< "$item")";
                  ''
                ) tfVarNames;
              in
              ''
                item="$(bw get item '${itemName}')"
                ${vars}
              ''
            ) itemNames;
          in
          final.writeShellApplication {
            name = "bw-terraform";
            runtimeInputs = [
              final.jq
              final.terraform
              final.bitwarden-cli
            ];
            text = ''
              if [ -z "$BW_SESSION" ]; then
              	BW_SESSION="$(bw unlock --raw)"
              	echo "Bitwarden session (export as BW_SESSION to avoid repeating entries): $BW_SESSION"
              	export BW_SESSION
              fi

              JQ_FIELD_SCRIPT='.fields | map(select(.name == $name))[0].value'
              ${exports}

              terraform "$@"
            '';
          };
      };
    };
}
