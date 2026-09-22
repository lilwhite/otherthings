az graph query `
    -q "Resources | where name =~ 'conp1weugvml-bifrost-001' | project name, type, subscriptionId, resourceGroup, location, tags, id" `
    --query "data" `
    -o json


$bifrostSub = "<SUBSCRIPTION-ID>"

az maintenance assignment list-subscription `
    --subscription $bifrostSub `
    -o json
