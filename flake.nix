{
  description = "Flake used to define terraform helper binary that can read variables from bitwarden";
  inputs = { };
  outputs =
    { ... }:
    let
      assertMsg = pred: msg: pred || builtins.throw msg;
      concatLines = builtins.concatStringsSep "\n";
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
                varNames = builtins.attrNames item;
                vars = builtins.map (
                  varName:
                  let
                    var = item.${varName};
                    script =
                      if var == "login.password" || var == "login.username" then
                        "jq -r '.${var}'"
                      else
                        "jq -r --arg name '${var}' \"$JQ_FIELD_SCRIPT\"";
                  in
                  assert assertMsg (builtins.match "^[a-zA-Z0-9_]+$" != null) "Invalid variable name: ${varName}";
                  ''
                    export ${varName}="$(${script} <<< "$item")";
                  ''
                ) varNames;
              in
              ''
                item="$(bw get item '${itemName}')"
                ${concatLines vars}
              ''
            ) itemNames;
          in
          prev.writeShellApplication {
            name = "bw-terraform";
            runtimeInputs = [
              prev.jq
              prev.terraform
              prev.bitwarden-cli
            ];
            text = ''
              if [ -z "$BW_SESSION" ]; then
              	BW_SESSION="$(bw unlock --raw)"
              	echo "Bitwarden session (export as BW_SESSION to avoid repeating entries): $BW_SESSION"
              	export BW_SESSION
              fi

              JQ_FIELD_SCRIPT='.fields | map(select(.name == $name))[0].value'
              ${concatLines exports}

              terraform "$@"
            '';
          };
      };
    };
}
