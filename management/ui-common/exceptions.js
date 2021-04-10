export class ValueError extends Error {
    constructor(msg) {
        super(msg);
    }
};

export class AssertionError extends Error {
}

export class AuthenticationError extends Error {
    constructor(caused_by_error, msg, response) {
        super(msg);
        this.caused_by = caused_by_error;
        this.response = response;
        if (!response && caused_by_error)
            this.response = caused_by_error.response;
    }
};
