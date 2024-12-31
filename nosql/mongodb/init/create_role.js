db.createRole({
    role: 'remote_role', 
    privileges: [{
        resource: {
            db: "",
            collection: ""
        }, actions: [
            "insert",
            "update",
            "find",
            "changeStream",
            "createIndex",
            "dropIndex",
            "remove"]
        }], roles: [] 
}); 