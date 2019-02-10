package tuhh.de.btdatalogger;

import android.annotation.SuppressLint;
import android.bluetooth.BluetoothDevice;
import android.os.Bundle;
import android.support.v7.app.AppCompatActivity;
import android.util.Log;
import android.view.View;
import android.widget.TextView;
import android.widget.Toast;

import com.harrysoft.androidbluetoothserial.BluetoothManager;
import com.harrysoft.androidbluetoothserial.BluetoothSerialDevice;
import com.harrysoft.androidbluetoothserial.SimpleBluetoothDeviceInterface;

import java.math.BigDecimal;
import java.nio.charset.Charset;
import java.util.ArrayDeque;
import java.util.Deque;
import java.util.List;

import io.reactivex.android.schedulers.AndroidSchedulers;
import io.reactivex.schedulers.Schedulers;

public class MainActivity extends AppCompatActivity {

	BluetoothManager bluetoothManager;
	SimpleBluetoothDeviceInterface deviceInterface;
	Deque<Byte> recievedData = new ArrayDeque<>(30);

	@Override
	protected void onCreate(Bundle savedInstanceState) {
		super.onCreate(savedInstanceState);
		setContentView(R.layout.activity_main);

		findViewById(R.id.disconnectButton).setVisibility(View.INVISIBLE);

		//TextView textView = (TextView) findViewById(R.id.temperature);
		//textView.setText(22 + " °C");

		// Setup our BluetoothManager
		bluetoothManager = BluetoothManager.getInstance();
		if (bluetoothManager == null) {
			// Bluetooth unavailable on this device :( tell the user
			Toast.makeText(this, "Bluetooth not available.", Toast.LENGTH_LONG).show(); // Replace context with your context instance.
		}
	}

	public void onConnectPress(View view) {
		BluetoothDevice device = null;

		List<BluetoothDevice> pairedDevices = bluetoothManager.getPairedDevicesList();
		for (BluetoothDevice one : pairedDevices) {
			if (one != null) {
				if (one.getName().equals("HC-05")) {
					device = one;
				}
				Log.d("Debug", "Device name: " + one.getName());
				Log.d("Debug", "Device MAC Address: " + one.getAddress());
			}
		}

		if (device != null) {
			connectDevice(device.getAddress());
			((TextView) findViewById(R.id.status)).setText(R.string.Connecting);
		} else {
			Toast.makeText(this, "Device not found", Toast.LENGTH_LONG).show();
		}
	}

	public void onDisconnectPress(View view) {
		bluetoothManager.closeDevice(deviceInterface);
		deviceInterface = null;
		((TextView) findViewById(R.id.status)).setText(R.string.Disconnected);
		findViewById(R.id.disconnectButton).setVisibility(View.INVISIBLE);
		findViewById(R.id.connectButton).setVisibility(View.VISIBLE);
	}


	@SuppressLint("CheckResult")
	private void connectDevice(String mac) {
		bluetoothManager.openSerialDevice(mac)
				.subscribeOn(Schedulers.io())
				.observeOn(AndroidSchedulers.mainThread())
				.subscribe(this::onConnected, this::onError);
	}

	private void onConnected(BluetoothSerialDevice connectedDevice) {
		// You are now connected to this device!
		// Here you may want to retain an instance to your device:
		deviceInterface = connectedDevice.toSimpleDeviceInterface();

		// Listen to bluetooth events
		deviceInterface.setListeners(this::onMessageReceived, this::onMessageSent, this::onError);

		((TextView) findViewById(R.id.status)).setText(R.string.Connected);

		findViewById(R.id.connectButton).setVisibility(View.INVISIBLE);
		findViewById(R.id.disconnectButton).setVisibility(View.VISIBLE);

		Toast.makeText(this, "Connected to BT Data Logger Board", Toast.LENGTH_LONG).show();

		// Let's send a message:
		//deviceInterface.sendMessage("Hello world!");
	}

	private void onMessageSent(String message) {
		// We sent a message! Handle it here.
		Toast.makeText(this, "Sent a message! Message was: " + message, Toast.LENGTH_LONG).show(); // Replace context with your context instance.
	}

	private void onMessageReceived(String message) {
		// We received a message! Handle it here.
		byte[] bytes = message.getBytes(Charset.forName("ASCII"));
		for (byte b : bytes) {
			recievedData.add(b);
		}
		/*char[] chars = message.toCharArray();
		if (chars.length < 12) {
			Toast.makeText(this, "Did not receive enough bytes", Toast.LENGTH_LONG).show();
			return;
		}*/
		/*for (char c : message.toCharArray()) {
			recievedData.add((byte) c);
		}*/

		readMessage();
	}

	@SuppressWarnings("ConstantConditions")
	private void readMessage() {
		boolean removed = false;
		while (recievedData.size() > 2) {
			// If we have some bytes, see if the First one is 123
			// and the second one is 132
			// Those are our sync bytes so we know where to start to read
			if (recievedData.poll() == 123) {
				// This will remove and read the first byte.
				// If it is 123 we check the next one.
				if (recievedData.peek() == 127) {
					// If that is 132 then we add the 123 back to the start
					// If not then something was wrong and we keep it removed
					recievedData.addFirst((byte) 123);
					break;
				}
			}
		}
		if (recievedData.size() < 15) {
			// We need to wait for more Data
			return;
		}
		// We have 14 or more bytes. Remove the first two bytes (sync bytes)
		recievedData.remove();
		recievedData.remove();
		// We are now left with 12 (or more) bytes.
		// reading the 12 bytes will give us the temperature and Humidity reading

		/*String s = "\n";
		for (byte b : recievedData.toArray(new Byte[0])) {
			s += b + "\n";
		}
		Log.d("Debug", s);*/

		// Each byte only has Data in its least significant 4 bits
		// So we need to extract 4 bits per byte, for 4 bytes to get an int (short)
		int temperatureData = (recievedData.poll() << 12) | (recievedData.poll() << 8) | (recievedData.poll() << 4) | recievedData.poll();
		// Calculate Temperature from the Data using the Formula found on the Sensors Datasheet
		float temperatureExact = ((float) temperatureData) / 100f;
		temperatureExact -= 40.1f;
		BigDecimal bd = new BigDecimal(temperatureExact);
		float temperature = bd.setScale(2, BigDecimal.ROUND_HALF_UP).floatValue();

		if (recievedData.peek() == 0) {
			// The First (half-) byte of the Humidity is always 0
			// sometimes this is not being sent, so ignore it if it is there
			recievedData.remove();
		}

		int humidityData = (recievedData.poll() << 8) | (recievedData.poll() << 4) | recievedData.poll();
		byte crcTempData = (byte) ((recievedData.poll() << 4) | recievedData.poll());
		byte crcHumData = (byte) ((recievedData.poll() << 4) | recievedData.poll());
		// Calculate Humidity from the Data using the Formula found on the Sensors Datasheet
		float humidityExact = (float) ( -2.0468 + (0.0367 * humidityData) + (-1.5955E-6 * humidityData * humidityData) );
		// Temperature Compensation for the Humidity
		humidityExact = (float) ( ((temperatureExact - 25.0) * (0.01 * (0.00008 * humidityData))) + humidityExact );
		bd = new BigDecimal(humidityExact);
		float humidity = bd.setScale(2, BigDecimal.ROUND_HALF_UP).floatValue();

		/*String temperatureString = Float.toString(temperature);
		int dot = temperatureString.indexOf('.');
		//Toast.makeText(this, "dot: " + dot + " lenght: " + temperatureString.length(), Toast.LENGTH_LONG).show();
		if (dot > -1) {
			if (temperatureString.length() > dot + 3) {
				temperatureString = temperatureString.substring(0, dot + 3);
			}
		}*/
		TextView textView = findViewById(R.id.temperature);
		textView.setText(temperature + " °C");

		textView = findViewById(R.id.humidity);
		textView.setText(humidity + " %");
		//Toast.makeText(this, "Received a message! Message was: " + message, Toast.LENGTH_LONG).show(); // Replace context with your context instance.
	}

	private void onError(Throwable error) {
		// Handle the error
		((TextView) findViewById(R.id.status)).setText(R.string.Disconnected);
		findViewById(R.id.disconnectButton).setVisibility(View.INVISIBLE);
		findViewById(R.id.connectButton).setVisibility(View.VISIBLE);
		Toast.makeText(this, "Connect Error: " + error.getMessage(), Toast.LENGTH_LONG).show();
		error.printStackTrace();
	}
}
