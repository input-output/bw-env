{
  description = "Flake used to create shell script that can assign bitwarden secrets to env variables";
  outputs =
    { ... }:
    let
      assertMsg = pred: msg: pred || builtins.throw msg;
      concatLines = builtins.concatStringsSep "\n";
      overlay = final: prev: {
        mkBwEnv =
          {
            items,
            name ? "bw-env",
            exe,
          }:
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
                    ${varName}="$(${script} <<< "$item")"
                    if [[ "''$${varName}" == "null" ]]; then
                      echo "Could not read ${varName} from ${itemName}" 1>&2
                      exit 1
                    fi
                    export ${varName}
                  ''
                ) varNames;
              in
              ''
                item="$(bw get item '${itemName}')"
                ${concatLines vars}
              ''
            ) itemNames;
          in
          final.writeShellApplication {
            inherit name;
            runtimeInputs = [
              final.jq
              (final.callPackage ./bitwarden-cli.nix { })
            ];
            text = ''
              if [ -z "''${BW_SESSION+x}" ]; then
              	BW_SESSION="$(bw unlock --raw)"
              	echo "Bitwarden session (export as BW_SESSION to avoid repeating entries): $BW_SESSION" 1>&2
              	export BW_SESSION
              fi

              JQ_FIELD_SCRIPT='.fields | map(select(.name == $'"name))[0].value"
              ${concatLines exports}

              exec "${exe}" "$@"
            '';
          };
      };
    in
    {
      overlays.default = overlay;
    };
}
