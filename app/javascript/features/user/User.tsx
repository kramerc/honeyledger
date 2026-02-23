import { useAppSelector } from "../../hooks";
import { selectUser } from "./userSlice";

export const User = () => {
  const user = useAppSelector(selectUser);

  if (!user) {
    return <p>No user logged in</p>;
  }

  return (
    <div>
      <h2>User State</h2>
      <p>
        ID: {user.id}
        <br />
        Email: {user.email}
      </p>
    </div>
  );
};
