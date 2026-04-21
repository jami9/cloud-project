# One-liner pour régénérer un token expiré
if ! openstack token issue --insecure >/dev/null 2>&1; then
    echo "Token expiré, génération d'un nouveau..."
    source ~/admin-openrc.sh
    openstack --insecure token issue
else
    echo "Token encore valide !"
fi
