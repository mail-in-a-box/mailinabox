
class DatabaseConnectionFactory(object):
    def connect(self):
        raise NotImplementedError()

    def close(self, conn):
        raise NotImplementedError()
    

    
