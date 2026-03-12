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
            "private_key_id": "8e65e5b21e66a0a102c5878cd1981a1d0f4e9267",
            "private_key": "-----BEGIN PRIVATE KEY-----\nMIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQC6YRZihpjXHPT8\nGJT97B0UpCudidcFVj+ffBBYSwCf+070VJm+0OuaU6TnL2UIemuzfhog11C+AjzF\nG7pja9RSb9uZu5ZMX7Lz5xkqIrfM+mBotcci8y5TzYWZ7ud9wRKMOwVYEzhk5adN\nNBCzasPCXRn31bocH1lb/Pkj/BXGmLYRQagdSO2eCgvLpu7WwYhQWHeQ5QIJyTwy\n3vFWTMS+r6uC3Ju5fCcW33GlOG/AwoZ4YWoYFxF7F3xy22xqkIW4LoQh47Np36cC\nXm/LkMXc4lVWXgIkrY6kIV+IxNyh45qn81Mb31iCiEin2cyI/H8cA5VDdC7NuAv8\nbdvjdkQbAgMBAAECggEAUteYpY6CHQtn8S3T+9GZU3VtVYbRJjQh73erpDMiQfno\nLD32YJRoRJ5tK70rQUt4171zS6mo3+wKquoaPNrO8x15FKoGskfPOQ49ZzcrT1by\nx1gU/Xnt2538hmFkT8cjwWTyiSVx6ZcSeARub/FCtf+/7SL4qEte4r5c1xvTagPw\nFkcQ1i6dBSbhOqrFf/tATqfW02wEVd+6qy+ooyq1GfkeTE7wQV/jtxlycIV6xu6r\n5d/tlUSXgUJ9qrqejrQpVCquqVcOSsP9q4+/lZuG59Cn58xH7zJ+x/BOT0XlJ8IC\nhe0x9d/eCvavYX2Laia9cAzAKA58G+1v3TKdZ15dYQKBgQDr+mnBkP3kicVwZJHh\nCGCED6tLZxW3vzUjZOHNLgibTpEar+XL2kkSBtshq0/6/0dJW3rj8IkLSI8uQbpP\nPfpHk1OcW2KDvGbbVUxf3s3ObDd5p5Bg4qIk1+EZF1olp+gRtdcmh0NmPTa59U0s\ndFWLEcSsrie0uQolJiMcoMG48wKBgQDKMVsiNXh6OGxqCNrx5+StwpULcU2UIXL+\n7JYgq39N1SoBbGUiTWb1Sxkye7pXgUwb8QOHo1N88dn1CKX/Z92ewini6BP4R0fA\n8NmmR2SqLhwI8CINN3o3CJBMWjbX1G3d6RiJbVhUrHNNENImR23Q6lxLX3lmkT9C\nnYicViESOQKBgQCMWeT6tsT7X6Hpxjcpk7Tr9vHXqBk3r2bohUDzqxR9Ys5VBBd2\nFn9tVFyS+vRYAeshS2KdHdw0tNRMG9W2+dLZLVwGXCgM2EqI24PQZZEc3Cpmle3+\nYe00Yp3EMapxSRtzJScxCDRjI7dgBPEAprSWQVwrpG2DRKcvDy7FASwXVwKBgQCS\nmqzopfqgLA835wnRwwGFmAP30wScNpCqFKNaNt9McRZPB+hgsdzIWNaBS0M2tZKY\n4+1aSOt9OeN+jvHFuerwdPpoAzyPlieJ11kI/tUXq+058dvO133vL29pXTRM1EOB\nVsUqyDT22D+WDm9BwCL5CyU2pZhh7UkAJTdrm+vIyQKBgDj1k0Pi9VTFjP0SKr63\nGBD18uJS8RLL70cu9P6Qpp1tk3NEM9wLlhR1XAq2E/hxMR0V3RMoapeoKeu+1PMl\n1StEHv6G60FnizySg9whZt2EBw9b2qr8/6PbP4b/3PeNl7hQ4hVABMO1GrExvJ2G\nQJ5Z4zWSZI6xbxa6bIaZciAY\n-----END PRIVATE KEY-----\n",
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

    return accessToken;
  }
}
