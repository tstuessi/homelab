# Adopt existing database into IaC
Adopting an existing postgres db into IaC is very simple since k8s acts as a reconciliation engine. Simply create the database CRD and apply it - some small modifications might be made in terms of database ownership and permissioning, but that shouldn't break anything existing.

Some care is required if there are already tables within the DB. Once the DB owner is changed, the following needs to be run to change ownership of the tables, functions, etc. to the new owner:

```
REASSIGN OWNED BY "<old_owner>" TO "<new_owner>"
```

After, ownership will have changed and everything should work as normal.