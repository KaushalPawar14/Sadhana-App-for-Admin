import 'package:googleapis_auth/auth_io.dart';

class AccessTokenFirebase {
  // first add endpoint url
  static String firebaseMessagingScope =
      "https://www.googleapis.com/auth/firebase.messaging";

  Future<String> getAccessToken() async {
    final client = await clientViaServiceAccount(
        ServiceAccountCredentials.fromJson(
          {
            "type": "service_account",
            "project_id": "folk-sadhana-app",
            "private_key_id": "dd598be36e9348ee0bdc8c81711793bbd2b8a0a6",
            "private_key": "-----BEGIN PRIVATE KEY-----\nMIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQDh7zTeTiLm0FYL\nVcBkszx/ktGfc8kGoizaT/XJa/GouS1sF38+z5eOIcMqUtAVmWhhM751g13VCZB1\npaXIgqTc3ZVdTs5moWKCE4+575GYQ5I+AofpQwchMKvvyBuFmwxThgT1yWFl/pFy\nNWbADa6x5p8nxlc/8hGMBEYFEKgoQVvD2Rc4mgpr0UOiW7769E0+tg1HzdboPdqt\nnHusWlfDj+QkV72hghn8zjUk04nl+ckkn+LAs+B+oy2TkZadwU9Mdt2MeUA0ydNV\nEZfiwcot2wt8ySu+hX2EoGaK4YCcjF2nd0PNiosz+pb8a587M6PGnpYbnbELFkHu\n89a3TW4nAgMBAAECggEAISi83yWjnLGV90rqFj1yEx0ms9rH9bfGknHq1lmH2aX3\n4yXdsIfCLAOLg8IstQbTWXTBLrkNg+9H6uRZXQDDloDU46FlzI1CCmo5jWX6Pdko\n9P3lGZiTSs08ZtA9LdIwMG/6eWJJb7E5goQQ5P39FjINSMak1oc+CQk1h5fGvkV2\nx1oTUIzmVHIMs9XJ0BYxihvFhZFGf9SBt629C0C0uvs+b0FrtEivfX/xIN2/XmFr\nnK/kJon50ib3DyuOX4ifHGtWXjkhG45SL8XvVPXL0Il4kKeiSAev/AX0NdfFvc5x\ntpkeKARt966/CvEYheNnqHFa+I5Wr9EqXIVX/iU7yQKBgQD2dBuun8g9Wo6zutFz\nhISBYbjO93YkrmNlLJbs7wdhmkuifxTrJ9DRIdkq4b3iaRYcNTLIBlbkEOGv8LUe\nmYkUiCEXN2NkUI8E56ezQn+3rssHre72wCNKc2MdhL15gMUz4lQf2jtakBCtOwk0\nkX6EkxEXMi6k8O79XM35MiZn/wKBgQDqr6Aqyu46vX3HA8C0utMihzaAwAatXaoH\n8z4mNTg9fERx6Zz4MnxrTdFRn3uw/HL8ePKf8Ja0iYV3q7Uu8Qsc1jw6yU0u+tP8\nFWSzRUUgLlttRKIoHuv11UNmi7yw+qMLqr1DZ/0mBIxoRD+hnFyf4KHVCqQ7TOZI\nGxQczGi52QKBgBuQjPARCvJhyIgtovOKpM9bwLHVV69umctdG1xQt8Cg40i/cfWD\nNIXPhVyYdwZ1vnVVNeLNYraLdNKa14ceoQhc2WahWUqFABoKVuVj0KkYsbigKZQL\nlWbkVPeeOxr13hiZfdM6M11Ds7nMWpE4nK/zSvwPLsxf7jsEQD1Y8Ja9AoGAdsuL\n0d2DFazRvCnEJDflpDa5eha5yov9A6U3MnQCEe2TX+4XDPPRUyfC6wRFwmMneXFn\nr1pDjwOF0fvS7P4K2AAB4OgA7+T75UCXBr/rq8yLbxYs1w4/9uKLCZ92VkeovMEi\nqLo8xD/NKwJRC2dw42T7xjFqzLGyZ5F9bs5xvJECgYEAoP4KPw454HhrM5pEttLj\nDvqxfc/1HSR4dl8jVISZC2pTfPd2YU8dHkxtKGYvqGvE3yFRNeNr4MpqBj9JrDWN\nDgyr1eUeRHkPLoW50OwQocXWIa90vOI3h62cRTgZkU63m8ho9RWPqHSWQ7aofV0e\nyyWxEYs7gTq4mcTHugWtejI=\n-----END PRIVATE KEY-----\n",
            "client_email": "firebase-adminsdk-4yxsp@folk-sadhana-app.iam.gserviceaccount.com",
            "client_id": "104797622401459366280",
            "auth_uri": "https://accounts.google.com/o/oauth2/auth",
            "token_uri": "https://oauth2.googleapis.com/token",
            "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs",
            "client_x509_cert_url": "https://www.googleapis.com/robot/v1/metadata/x509/firebase-adminsdk-4yxsp%40folk-sadhana-app.iam.gserviceaccount.com",
            "universe_domain": "googleapis.com"
          },
        ), [firebaseMessagingScope]
    );
    final accessToken = client.credentials.accessToken.data;

    client.close(); // ✅ VERY IMPORTANT

    return accessToken;
  }
}
