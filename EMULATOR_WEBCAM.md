# Use Your Laptop Camera in the Android Emulator

The app uses the camera that the **emulator** provides. By default the emulator uses a virtual/fake camera. To use your laptop’s real webcam you must change the emulator’s camera settings.

## Steps (Android Studio)

1. **Open Device Manager**  
   In Android Studio: **Tools → Device Manager** (or **Tools → AVD Manager**).

2. **Edit your virtual device**  
   Click the **pencil (Edit)** icon next to the AVD you use (e.g. Pixel 6).

3. **Open advanced settings**  
   Click **Show Advanced Settings** (at the bottom).

4. **Set the camera to your webcam**  
   Find the **Camera** section:
   - Set **Back** to **Webcam0** (the app is set to use the rear camera so it will use your laptop camera).

   Do **not** set both Front and Back to Webcam0 (it can cause issues). Use only Back = Webcam0.

5. **Save and restart the emulator**  
   Click **Finish**, then **Cold Boot Now** (or close the emulator and start it again).

6. **Test in the app**  
   Open the chat screen, tap the camera icon, and take a photo. It should use your laptop camera.

## If it still uses the virtual camera

- Fully close the emulator and start it again after changing the setting.
- Make sure no other app (e.g. Zoom, Teams) is using the webcam.
- Ensure **Back** camera is set to **Webcam0** (the chat screen is set to use the rear camera).
